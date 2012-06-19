module Base
  def ssh
    host = singleHost()
    system "echo '#{@user_settings['mykey']}' > /tmp/mykey;chmod 600 /tmp/mykey"
    system "ssh -i /tmp/mykey admin@#{host}"
    system "rm /tmp/mykey 2> /dev/null"
  end
  def scpfrom
  end
  def scpto
  end
  def chefrun
    if sshReachable?
      hosts = getCluster()
      hosts.peach do |host|
        host_settings = {
          'this_server' => host,
          'run_list'    => [ "recipe[#{@chefsettings['normal_recipe']}]" ]
        }
        json = @chefsettings.merge!(host_settings).to_json
        run = [
          "cd ~admin/ops; git pull",
          "echo '#{json}' > ~admin/solo.json",
          "sudo chef-solo -c ~admin/ops/cookbooks/solo.rb -j ~admin/solo.json"
        ]
        ap json
        putkey(host)
        sshcmd(host, run)
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
        host_settings = {
          'this_server' => host,
          'run_list'    => [ "recipe[#{@chefsettings['deploy_recipe']}]" ],
          'do_migrate'  => @args[:migrate],
          'branch'      => @args[:branch]
        }
        json = @chefsettings.merge!(host_settings).to_json
        run = [
          "cd ~admin/ops; git pull",
          "echo '#{json}' > ~admin/solo.json",
          "sudo chef-solo -c ~admin/ops/cookbooks/solo.rb -j ~admin/solo.json"
        ]
        ap json
        sshcmd(host, run)
      end
    end
  end
  def web
    if sshRachable?
      hosts = getCluster()
      if @args[:enable]
        hosts.peach do |host|
          sshcmd(host, "sudo -u #{@env_settings['user']} rm /data/#{@args[:app]}/shared/system/maintenance.html 2> /dev/null")
          puts "#{host} : web enabled"
        end
      end
      if @args[:disable]
        hosts.peach do |host|
          sshcmd(host, "sudo -u #{@env_settings['user']} ln -sf /data/#{@args[:app]}/current/public/maintenance.html /data/#{@args[:app]}/shared/system/maintenance.html")
          puts "#{host} : web disabled"
        end
      end
    end
  end
  def init
    if @args[:zone] == 'nil'
      zone = @env_settings['default_zone']
    else
      zone = @args[:zone]
    end
    az = zone.chop
    if @args[:arch] == 'nil'
      arch = @env_settings['default_arch']
    else
      arch = @args[:arch]
    end
    ami = @env_settings['amis'][az][arch]['id']
    user = @env_settings['amis'][az][arch]['user']
    if @args[:node] == 'solo' && isCluster?
      hosts = getCluster()
    end
    if @args[:node] != 'solo' || !isCluster?
      hosts = [ singleHost() ]
    end
    begin
      initscript = File.read(File.expand_path(File.dirname(__FILE__) + "/init/#{@env_settings['amis'][az][arch]['os']}.erb"))
    rescue
      puts "There is no init file for your OS, aborting."
      exit 100
    end
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
        'branch'      => @args[:branch]
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
          sshcmd(ip, ["exit 0"], user, key)
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
          "echo '#{json}' > ~admin/solo.json",
          "sudo chef-solo -c ~admin/ops/cookbooks/solo.rb -j ~admin/solo.json"
        ]
      sshcmd(ip, run, user, key)
    end
  end
end
