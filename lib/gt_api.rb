class Nodes
  include HTTParty
  base_uri $BASEURI

  def initialize(user, apikey)
    @auth = { 
