module Base
  def ssh
    host = singleHost()
    system "echo '#{@user_settings['mykey']}' > /tmp/mykey;chmod 600 /tmp/mykey"
    system "ssh -i /tmp/mykey admin@#{host}"
    system "rm /tmp/mykey 2> /dev/null"
  end
  def scpfrom
    require 'net/scp'
    # net-scp does not handle ~ well...
    remote = ARGV[-2].gsub('~', "/data/admin")
    local = ARGV[-1].gsub('~', ENV['HOME'])
    host = singleHost()
    session = Net::SSH.start(host, 'admin', :key_data => [@user_settings['mykey']], :config => false, :keys_only => true, :paranoid => false)
    session.scp.download!(remote, local, :recursive => true) do |ch, name, sent, total|
      print "\r#{name}: #{(sent.to_f * 100 / total.to_f).to_i}%"
    end
  end
  def scpto
    require 'net/scp'
    # net-scp does not handle ~ well...
    remote = ARGV[-1].gsub(/~/, "/data/admin")
    local = ARGV[-2].gsub(/~/, ENV['HOME'])
    host = singleHost()
    session = Net::SSH.start(host, 'admin', :key_data => [@user_settings['mykey']], :config => false, :keys_only => true, :paranoid => false)
    session.scp.upload!(local, remote, :recursive => true) do |ch, name, sent, total|
      print "\r#{name}: #{(sent.to_f * 100 / total.to_f).to_i}%"
    end
  end
  def chefrun
    if sshReachable?
      hosts = getCluster()
      hosts.peach do |host|
        run_list = $c.detect{|f| f[:hostname] == host }[:recipe]
        unless @args[:recipe].to_s == 'nil'
          run_list = @args[:recipe]
        end
        recipeRun(host, run_list)
      end
    end
  end
  def info
    hosts = getCluster()
    hosts.peach do |host|
      run = [ "~admin/ops/scripts/gtinfo.rb" ]
      sshcmd(host, run)
    end
  end
  def log
    logs = YAML::load(File.open('./log.yml'))[@args[:logtype]]
    run = Array.new
    logs.each do |log|
      run += "tail -f -n#{@user_settings['taillines']} #{log}"
    end
    hosts = getCluster()
    hosts.peach do |host|
      sshcmd(host, run)
    end
  end
  def deploy
    if sshReachable?
      hosts = getCluster()
      hosts.peach do |host|
        run_list = $c.detect{|f| f[:hostname] == host }[:deploy]
        unless @args[:branch].to_s == 'nil'
          @branch = @args[:branch]
        end
        @deploy_settings = {
          'branch' => @branch,
          'app_name' => @args[:app],
          'rollback' => false
        }
        recipeRun(host, run_list, @deploy_settings)
      end
    end
  end
  def rollback
    if sshReachable?
      hosts = getCluster()
      hosts.peach do |host|
        run_list = $c.detect{|f| f[:hostname] == host }[:deploy]
        @deploy_settings = {
          'app_name' => @args[:app],
          'rollback' => true
        }
        recipeRun(host, run_list, @deploy_settings)
      end
    end
  end
  def toggle
    if sshRachable?
      hosts = getCluster()
      if @args[:enable]
        @settings = { 'toggle' => 'enable' }
      end
      if @args[:disable]
        @settings = { 'toggle' => 'disable' }
      end
       hosts.peach do |host|
        recipeRun(host, 'toggle', @deploy_settings)
      end
    end
  end
  def add
    $c = cgen()
    begin
      @initfile = YAML::load(File.open(@args[:template]))
    rescue
      puts "Please input a valid yaml file for the template"
    end
    if @initfile['number'].to_i == 0
      numbers = [0]
      $c.each do |host|
        if host[:role] == @initfile['role']
          numbers << host[:number]
        end
      end
      number = numbers.max+1
    else
      number = @initfile['role'].to_i
    end
    AWS.config(:access_key_id => @user_settings['aws_id'], :secret_access_key => @user_settings['aws_secret'], :ec2_endpoint => "ec2.amazonaws.com")
    ec2 = AWS::EC2.new
    init = {
      :number => number,
      :hostname => "#{@initfile['role']}-#{@initfile['environment']}-#{number}.#{@initfile['domain']}",
      :recipe => 'init',
      :run_list => ["recipe[init]"]
    }
    @initfile.keys.each do |key|
      @initfile[(key.to_sym rescue key) || key] = @initfile.delete(key)
    end
    init.merge! @initfile
    @json = init.to_json
    script = <<INITSCRIPT
#!/usr/bin/env bash
apt-get install -y zsh git libssl-dev ruby1.9.1-full build-essential
REALLY_GEM_UPDATE_SYSTEM=true gem update --system
gem install --bindir /usr/local/bin --no-ri --no-rdoc chef
cat << 'EOFKEY' > /root/.ssh/id_rsa
#{init[:identity]}
EOFKEY
chmod 600 /root/.ssh/id_rsa
echo 'StrictHostKeyChecking no' > /root/.ssh/config
git clone -b #{init[:chefbranch]} #{init[:chefrepo]} /root/ops
echo '#{@json}' > /root/init.json
chef-solo -c /root/ops/cookbooks/init.rb -j /root/init.json && (r53_update.sh; rm /root/.ssh/id_rsa; userdel -r ubuntu)
INITSCRIPT
    instance = ec2.instances.create(:image_id => init[:ami], :availability_zone => @args[:zone], :instance_type => init[:itype], :key_name => init[:keyname], :security_group_ids => init[:sg], :user_data => script)
    instance.add_tag('Name' , :value => "#{init[:role]}-#{init[:environment]}-#{number}")
    instance.add_tag('dns', :value => "#{init[:role]}-#{init[:environment]}-#{number}.#{init[:domain]}")
    instance.add_tag('gaptool', :value => "{:role => '#{init[:role]}', :number => #{number}, :environment => '#{init[:environment]}', :apps => '#{init[:apps].to_s}'}")
    sleep 2
    File.open(File.expand_path("#{ENV['HOME']}/.gaptool-ma/aws.yml"), 'w') {|f| f.write(cgen().to_yaml)}
  end
  def init
   itype = @env_settings['applications'][@args[:app]][@args[:environment]]['itype']
    keyname = @user_settings['awskeys'][az]
    key = @user_settings['initkeys'][keyname]
    sg = @env_settings['applications'][@args[:app]][@args[:environment]]['sg']
    AWS.config(:access_key_id => @user_settings['aws_id'], :secret_access_key => @user_settings['aws_secret'], :ec2_endpoint => "ec2.#{az}.amazonaws.com")
    ec2 = AWS::EC2.new
    hosts.peach do |host|
      host_settings = {
        'this_server' => host,
        'run_list'    => [ "recipe[#{@chefsettings['init_recipe']}]" ],
        'do_migrate'  => @args[:migrate],
        'branch'      => @args[:branch],
        'app_user'    => @env_settings['user'],
        'app_name'    => @args[:app]
      }
      json = @chefsettings.merge!(host_settings).to_json
      instance = ec2.instances.create(:image_id => ami, :availability_zone => zone, :instance_type => itype, :key_name => keyname, :security_group_ids => sg)
      print "Waiting for instanace to start".color(:cyan)
      while instance.status != :running do
        sleep 5
        print ".".color(:yellow)
      end
      puts ""
      print "Waiting for SSH to respoond".color(:cyan)
      loop do
        begin
          ip = instance.ip_address
          sshcmd(ip, ["exit 0"], :user => user, :key => key)
          break
        rescue
          print ".".color(:yellow)
        end
        sleep 2
      end
      puts "Sleeping another 5s for disks to settle".color(:cyan)
      sleep 5
      ip = instance.ip_address
      puts ""
      instance.add_tag('dns', :value => host)
      instance.add_tag('app', :value => @args[:app])
      instance.add_tag('environment', :value => @args[:environment])
      instance.add_tag('Name', :value => host.sub(".#{@env_settings['domain']}", ""))
      instance.add_tag('node', :value => @args[:node])
      render = ERB.new(initscript)
      run = render.result(binding).split(/\n/)
      run += [
          "echo '#{json}' > /tmp/solo.json",
          "sudo su -c 'chef-solo -c ~admin/ops/cookbooks/solo.rb -j /tmp/solo.json'",
          "sudo rm /tmp/solo.json"
        ]
      sshcmd(ip, run, :user => user, :key => key)
    end
  end
end
