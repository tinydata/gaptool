def setup
  yaml = Hash.new
  unless File.directory?("#{ENV['HOME']}/.gaptool") || File.exists?("#{ENV['HOME']}/.gaptool")
    puts "Welcome to gaptool setup\nThis will set up your ~/.gaptool configuration\nYou will need very little info here if you are NOT creating new nodes (e.g. just configuring and deploying)\nIf you ARE using the the 'init' facility, you will need your AWS ID, Secret, and EC2 PEM keys for relevant Availability Zones.".color(:red)
    puts "Starting with your AWS ID/Secret.\nIf you don't have these, just press enter.".color(:cyan)
    print "Enter your AWS ID: "
    yaml['aws_id'] = gets.chomp
    print "enter your AWS Secret: "
    yaml['aws_secret'] = gets.chomp
    puts "Now we will go through each AWS zone\nEnter a key NAME you have in each zone that you want associated with gaptool nodes.\nIf you don't have one, press enter.\nAfter each key, paste the path to the downloaded key.".color(:cyan)
    zones = [ 'us-east-1', 'us-west-1', 'us-west-2', 'eu-west-1', 'ap-southeast-1', 'ap-northeast-1', 'sa-east-1' ]
    yaml['awskeys'] = Hash.new
    yaml['initkeys'] = Hash.new
    zones.each do |zone|
      print "#{zone}: "
      yaml['awskeys'][zone] = gets.chomp
      if yaml['awskeys'][zone] != ''
        print "Path to #{zone}.pem: "
        yaml['initkeys'][yaml['awskeys'][zone]] = File.read(File.expand_path(gets.chomp))
      end
    end
    key = OpenSSL::PKey::RSA.new 2048
    type = key.ssh_type
    data = [ key.to_blob ].pack('m0')
    yaml['mykey'] = key.to_pem
    yaml['mypub'] = "#{type} #{data}"
    Dir.mkdir("#{ENV['HOME']}/.gaptool")
    Dir.mkdir("#{ENV['HOME']}/.gaptool/plugins")
    File.open("#{ENV['HOME']}/.gaptool/plugins.yml", "w") {}
    File.open(File.expand_path("~/.gaptool/user.yml"), 'w') {|f| f.write(yaml.to_yaml) }
    puts "Your ~/.gaptool directory and user.yml have been configured\nPlease ask your administrator to provide you with a env.yml\nAdd the following public key to your github profile (or your git repo server)\nas well as in the authorized_keys file in your chef recipe for the admin user.".color(:cyan)
    puts yaml['mypub']
    exit 0
  end
end
setup()

$dist_plugins = [ 'Base' ]
if YAML::load(File.open("#{ENV['HOME']}/.gaptool/plugins.yml"))
  $plugins = $dist_plugins + YAML::load(File.open("#{ENV['HOME']}/.gaptool/plugins.yml"))
else
  $plugins = $dist_plugins
end

$commands = Hash.new
$plugins.each do |plugin|
  if $dist_plugins.include? plugin
    $commands.merge!(YAML::load(File.open(File.expand_path(File.dirname(__FILE__) + "/plugins/#{plugin}/config.yml"))))
  else
    $commands.merge!(YAML::load(File.open("#{ENV['HOME']}/.gaptool/plugins/#{plugin.to_s}/config.yml")))
  end
end

cmd = ARGV.shift
if !$commands.keys.include?(cmd) || cmd.nil?
  puts "Invalid option, please select one of the following commands:"
  $commands.keys.each do |command|
    puts "  #{command}"
  end
  exit 1
else
  cmd_opts = Trollop::options do
    $commands[cmd].each_key do |key|
      if $commands[cmd][key]['type'].nil?
        opt key.to_sym, $commands[cmd][key]['help'], :short => $commands[cmd][key]['short'], :default => $commands[cmd][key]['default']
      else
        opt key.to_sym, $commands[cmd][key]['help'], :short => $commands[cmd][key]['short'], :default => $commands[cmd][key]['default'], :type => $commands[cmd][key]['type'].to_sym
      end
    end
  end
end

class GTBase
  def isCluster?
    if @env_settings['applications'][@args[:app]][@args[:environment]]['cluster']
      return true
    else
      return false
    end
  end
  def getCluster
    hosts = Array.new
    if isCluster?
      @env_settings['applications'][@args[:app]][@args[:environment]]['cluster'].each do |node|
        hosts << "#{@args[:app]}-#{@args[:environment]}-#{node}.#{@env_settings['domain']}"
      end
    else
      hosts << "#{@args[:app]}-#{@args[:environment]}.#{@env_settings['domain']}"
    end
    return hosts
  end
  def sshcmd(host, commands, options = {})
    if options[:user]
      user = options[:user]
    else
      user = 'admin'
    end
    if options[:key]
      key = options[:key]
    else
      key = @user_settings['mykey']
    end
    Net::SSH.start(host, user, :key_data => [key], :config => false, :keys_only => true, :paranoid => false) do |ssh|
      commands.each do |command|
        if !options[:quiet]
          puts command.color(:cyan)
        end
        ssh.exec! command do
          |ch, stream, line|
          if !options[:quiet]
            puts "#{host.color(:yellow)}:#{line}"
          end
        end
      end
    end
  end
  def putkey(host)
    breakkey = @user_settings['mykey'].gsub(/\n/,'###')
    run = [
      "rm ~admin/.ssh/key 2> /dev/null",
      "echo '#{breakkey}' > /tmp/key",
      "cat /tmp/key|perl -pe 's/###/\\n$1/g' > ~admin/.ssh/key",
      "echo \"IdentitiesOnly yes\\nHost *\\n  StrictHostKeyChecking no\\n  IdentityFile ~/.ssh/key\" > ~admin/.ssh/config",
      "chmod 600 ~admin/.ssh/key",
      "chmod 600 ~admin/.ssh/config",
      "sudo rm ~#{@env_settings['user']}/.ssh/key",
      "sudo cp ~admin/.ssh/key ~#{@env_settings['user']}/.ssh/",
      "sudo cp ~admin/.ssh/config ~#{@env_settings['user']}/.ssh/",
      "sudo chown #{@env_settings['user']}:#{@env_settings['user']} ~#{@env_settings['user']}/.ssh/key",
      "sudo chown #{@env_settings['user']}:#{@env_settings['user']} ~#{@env_settings['user']}/.ssh/config",
      "sudo chmod 600 ~#{@env_settings['user']}/.ssh/key",
      "sudo chmod 600 ~#{@env_settings['user']}/.ssh/config",
      "rm /tmp/key"
    ]
    sshcmd(host, run, :quiet => true)
  end
  def sshReachable?
    hosts = getCluster()
    hosts.each do |host|
      begin
        puts "Checking SSH to: #{host}"
        sshcmd(host, ["exit 0"], :quiet => true)
      rescue
        puts "ERROR: Could not ssh to #{host}\nEither your connection is failing or AWS is having routing issues.\nAborting."
        exit 255
        return false
      end
    end
    return true
  end
  def singleHost
    if @args[:node] == 'solo' && isCluster?
      puts "The environment you're accessing is a cluster.\nYou've selected an action that acts only on a single node, but have not specified a node with --node/-n\nAborting."
      exit 100
    end
    if isCluster?
      return "#{@args[:app]}-#{@args[:environment]}-#{@args[:node]}.#{@env_settings['domain']}"
    else
      return "#{@args[:app]}-#{@args[:environment]}.#{@env_settings['domain']}"
    end
  end
  def initialize(args)
    @args = args
    if ENV['GT_ENV_SETTINGS']
        @env_settings = YAML::load(File.open(File.expand_path(ENV['GT_ENV_CONFIG'])))
    else
        @env_settings = YAML::load(File.open(File.expand_path("#{ENV['HOME']}/.gaptool/env.yml")))
    end
    if ENV['GT_USER_SETTINGS']
        @user_settings = YAML::load(File.open(File.expand_path(ENV['GT_USER_CONFIG'])))
    else
        @user_settings = YAML::load(File.open(File.expand_path("#{ENV['HOME']}/.gaptool/user.yml")))
    end
    chef_extra = {
      'rails_env' => @args[:environment],
      'server_names' => getCluster()
    }
    @chefsettings = @env_settings['applications'][@args[:app]][@args[:environment]]
    @chefsettings.merge!(@args)
    @chefsettings.merge!(chef_extra)
  end
end

class GTCluster < GTBase
  $plugins.each do |plugin|
    if $dist_plugins.include?(plugin)
      require File.expand_path(File.dirname(__FILE__) + "/plugins/#{plugin}/plugin.rb")
    else
      require File.expand_path(ENV['HOME'] + "/.gaptool/plugins/#{plugin}/plugin.rb")
    end
    include Object.const_get(plugin)
  end
end



cluster = GTCluster.new(cmd_opts)
cluster.send cmd
