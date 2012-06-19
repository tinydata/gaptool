module SamplePlugin
  def reboot
    if sshReachable?
      hosts.peach do |host|
        run = [ "sudo reboot" ]
        sshcmd(host, run)
      end
    end
  end
  def test
    puts "things worked!"
  end
end
