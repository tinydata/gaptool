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
      run_list = $c.detect{|f| f[:role] == @args[:role] }[:recipe] || @args[:recipe]
      hosts = getCluster()
      hosts.peach do |host|
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
        begin
          run_list = $apps[@args[:app]][:deploy]
        rescue
          run_list = 'deploy'
        end
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
        if host[:role] == @initfile['role'] && host[:environment] == @initfile['environment']
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
while [ ! -b '/dev/xvdf' ]; do sleep 1; done
while [ ! -b '/dev/xvdg' ]; do sleep 1; done
chef-solo -c /root/ops/cookbooks/init.rb -j /root/init.json && (r53_update.sh; rm /root/.ssh/id_rsa; userdel -r ubuntu)
INITSCRIPT
    instance = ec2.instances.create(:image_id => init[:ami], :availability_zone => @args[:zone], :instance_type => init[:itype], :key_name => init[:keyname], :security_group_ids => init[:sg], :user_data => script)
    sleep 1 until instance.status == :running
    volume = ec2.volumes.create(:size => init[:datasize], :availability_zone => @args[:zone])
    attachment = volume.attach_to(instance, "/dev/sdf")
    vol2id = 'nil'
    if init[:environment] == 'production'
      volume2 = ec2.volumes.create(:size => init[:datasize], :availability_zone => @args[:zone])
      attachment2 = volume2.attach_to(instance, "/dev/sdg")
      sleep 1 until attachment2.status != :attaching
      vol2id = volume2.id
    end
    instance.add_tag('Name' , :value => "#{init[:role]}-#{init[:environment]}-#{number}")
    instance.add_tag('dns', :value => "#{init[:role]}-#{init[:environment]}-#{number}.#{init[:domain]}")
    instance.add_tag('gaptool', :value => "{:role => '#{init[:role]}', :number => #{number}, :environment => '#{init[:environment]}', :apps => '#{init[:apps].to_s}', :volid => '#{volume.id}', :vol2id => '#{vol2id}'}")
    sleep 2
    File.open(File.expand_path("#{ENV['HOME']}/.gaptool-ma/aws.yml"), 'w') {|f| f.write(cgen().to_yaml)}
  end
end
