require 'rrobots'
require "#{File.dirname(__FILE__)}/utils/wall"
require "#{File.dirname(__FILE__)}/utils/shooter"

class Wallshooter
  include Robot
  include WallUtil
  include ShooterUtil

  def tick events
    wall_move
    quick_shoot
  end
end
