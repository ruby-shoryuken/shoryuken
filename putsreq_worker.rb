require 'net/http'

class PutsReqWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default', auto_delete: true

  def perform(sqs_msg, id)
    uri = URI('http://putsreq.com/v52LN17oegHRiETlcuUA')
    Net::HTTP.post_form(uri, id: id)
  end
end
