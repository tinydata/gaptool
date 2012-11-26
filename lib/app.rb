#!/usr/bin/env ruby
require 'rainbow'
require 'peach'
require 'json'
require 'clamp'
require 'typhoeus'
#require 'net-ssh'
#require 'net-scp'

require "./lib.rb"


class InitCommand < Clamp::Command
  option ["-r", "--resource"], "RESOURCE", "Resource name to initilize", :required => true
  option ["-e", "--environment"], "ENVIRONMENT", "Which environment, e.g. production", :required => true
  def execute
    puts resource
    puts environment
  end

end

class SshCommand < Clamp::Command
  option ["-r", "--resource"], "RESOURCE", "Resource name to ssh to", :required => true
  option ["-e", "--environment"], "ENVIRONMENT", "Which environment, e.g. production", :required => true
  option ["-n", "--number"], "NUMBER", "Node number, leave blank to query avilable nodes", :require => false

  def execute
    if number?
      `ssh admin@#{resource}-#{environment}-#{number}.#{DOMAIN}`
    else
      puts "No node number selected; querying provider"
      gethosts(resource, environment).each do |host|
        puts host
      end
      puts "Select number (just the number):"
      number = gets
      `ssh admin@#{resource}-#{environment}-#{number}.#{DOMAIN}`
    end
  end
end

class ChefrunCommand < Clamp::Command

end

class DeployCommand < Clamp::Command

end

class MainCommand < Clamp::Command

  subcommand "init", "Create new application cluster", InitCommand
  subcommand "ssh", "ssh to cluster host", SshCommand
  subcommand "chefrun", "chefrun on a resource pool", ChefrunCommand
  subcommand "deploy", "deploy on an application", DeployCommand

end

MainCommand.run
