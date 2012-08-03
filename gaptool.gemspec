Gem::Specification.new do |s|
  s.name = "gaptool"
  s.version = "0.10.8"
  s.authors = ['Matt Bailey']
  s.email = ['m@mdb.io']
  s.homepage = 'http://mdb.io'
  s.summary = 'EC2 application deployment, initialization and configuration tool'
  s.description = 'This command line tool will service a chef repo for building out, configuring, and deploying environments in EC2 and EC2 compatable infrastructure clouds'
  s.files = `git ls-files`.split("\n")
  s.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }

  s.add_dependency "net-ssh"
  s.add_dependency "net-scp"
  s.add_dependency "trollop"
  s.add_dependency "aws-sdk"
  s.add_dependency "json"
  s.add_dependency "peach"
  s.add_dependency "rainbow"
end

