require 'ap'

$dist_plugins = [ 'Base' ]
$plugins = $dist_plugins + YAML::load(File.open("#{ENV['HOME']}/.gaptool/plugins.yml"))

$commands = Hash.new
$plugins.each do |plugin|
  if plugin == 'Base'
    $commands.merge!(YAML::load(File.open(File.expand_path(File.dirname(__FILE__) + '/plugins/Base/config.yml'))))
  else
    $commands.merge!(YAML::load(File.open("#{ENV['HOME']}/.gaptool/plugins/#{plugin.to_s}/config.yml")))
  end
end

cmd = ARGV.shift
if !$commands.keys.include?(cmd)
  puts "Invalid option, please select one of the following commands:"
  $commands.keys.each do |command|
    puts "  #{command}"
  end
  exit 1
else
  cmd_opts = Trollop::options do
    $commands[cmd].each_key do |key|
      opt key.to_sym, $commands[cmd][key]['help'], :short => $commands[cmd][key]['short'], :default => $commands[cmd][key]['default'], :type => $commands[cmd][key]['type'].to_sym
    end
  end
end

class GTBase
  private
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
  def sshcmd(host, commands)
    Net::SSH.start(host, 'admin', :key_data => [@user_settings['mykey']], :config => false, :keys_only => true, :paranoid => false) do |ssh|
      commands.each do |command|
        ssh.exec! command do
          |ch, stream, line|
          puts "*** #{host} :: #{line}"
        end
      end
    end
  end
  def sshReachable?
    hosts = getCluster()
    hosts.each do |host|
      begin
        puts "Checking SSH to: #{host}"
        sshcmd(host, ["exit 0"])
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
  public
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
      'rails_env' => @args['environment'],
      'server_names' => getCluster(),
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
