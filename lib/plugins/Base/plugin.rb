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
          'run_list' => [ "recipe[#{@chefsettings['normal_recipe']}]" ]
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
  end
  def log
  end
  def deploy
  end
  def web
  end
  def init
  end
end
