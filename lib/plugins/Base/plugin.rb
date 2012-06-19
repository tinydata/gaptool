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
        sshcmd(host, run)
      end
    end
  end
  def info
    hosts = getCluster()
    hosts.peach do |host|
      run = [ "cd ~admin/ops; git pull", "~admin/ops/scripts/gtinfo.rb" ]
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
    AWS.config(:access_key_id => $user_settings['aws_id'], :secret_access_key => $user_settings['aws_secret'], :ec2_endpoint => $env_settings['ec2_endpoint'])
    ec2 = AWS::EC2.new
    zone = $env_settings['default_zone']
    if @args[:zone]
      zone = @args[:zone]
    end
    arch = $env_settings['default_arch']
    if @args[:arch]
      arch = @args[:arch]
    end
    ami = $env_settings[:amis][zone][arch]['id']
    if @args[:node] != 'solo'
      hosts = getCluster()
    else
      hosts = [ singlehost() ]
    end
    itype = $env_settings['applications'][@args[:app]][@args[:environment]]['itype']
    keyname = $user_settings['awskeys'][zone]
    key = $user_settings['initkeys'][keyname]
    sg = @env_settings['applications'][@args[:app]][@args[:environment]]['sg']
    hosts.peach do |host|
      host_settings = {
        'this_server' => host,
        'run_list'    => [ "recipe[#{@chefsettings['init_recipe']}]" ],
        'do_migrate'  => @args[:migrate],
        'branch'      => @args[:branch]
      }
      json = @chefsettings.merge!(host_settings).to_json
      instance = ec2.instances.create(:image_id => ami, :availability_zone => zone, :instance_type => itype, :key_name => key, :security_group_ids => sg)
      sleep 45
      instance.add_tag('dns', :value => host)
      instance.add_tag('app', :value => @args[:app])
      instance.add_tag('environment', :value => @args[:environment])
      instance.add_tag('Name', :value => host.sub(".#{$env_settings['domain']}", ""))
      instance.add_tag('node', :value => @args[:node])
      
    end
  end
end
