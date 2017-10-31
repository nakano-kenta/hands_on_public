require 'rrobots'
require "#{File.dirname(__FILE__)}/utils/shooter"

class Shooter
  include Robot
  include ShooterUtil

  def tick events
    quick_shoot
  end
end
