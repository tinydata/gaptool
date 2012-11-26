require 'httparty'
require 'awesome_print'
require 'json'

class GaptoolServer
  include HTTParty
  base_uri 'http://localhost:9393'

  def initialize(user, apikey)
    @auth = { 'X-GAPTOOL-USER' => user, 'X-GAPTOOL-KEY' => apikey}
  end

  def getonenode(role, environment, number)
    options = {:headers => @auth}
    JSON::parse self.class.get("/host/#{role}/#{environment}/#{number}", options)
  end

  def getenvroles(role, environment)
    options = {:headers => @auth}
    JSON::parse self.class.get("/hosts/#{role}/#{environment}", options)
  end

end


