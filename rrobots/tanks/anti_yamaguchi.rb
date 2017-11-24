require 'rrobots'
require "#{File.dirname(__FILE__)}/utils/sample"

class AntiYamaguchi
  include Robot
  include SampleUtil

  def tick events
    @random_angle ||= 0
    @random_angle = SecureRandom.random_number * 90 - 45 if time % 25 == 0
    @turn_angle = 0
    scan_for_fire
    target = @scanned_by_name.values.compact.select{|robot|
      (time - robot[:latest]) < 8
    }.first
    if target
      @turn_angle = (target[:direction] - heading)
      if target and target[:distance] < 300
        accelerate 1
      else
        @turn_angle += @random_angle
        accelerate_with_random 1, true
      end
      @turn_angle -= 360 if @turn_angle > 180
      @turn_angle += 360 if @turn_angle < -180
      turn @turn_angle
      # shoot_uniform_speed if target[:distance] < 350
      shoot_uniform_speed
    else
      accelerate_with_random 1, true
    end
  end
end
