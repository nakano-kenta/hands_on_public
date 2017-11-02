require 'rrobots'
require "#{File.dirname(__FILE__)}/utils/shooter"
require "#{File.dirname(__FILE__)}/utils/wall"

require 'securerandom'

class RandomShooter
  include Robot
  include WallUtil
  include ShooterUtil

  def tick events
    accelerate 1
    if @will_fire
      fire 3
      @will_fire = false
    end

    if x < @size * 2
      turn -heading
      return
    elsif y < @size * 2
      turn 270 - heading
      return
    elsif x > battlefield_width - @size * 2
      turn 180 - heading
      return
    elsif y > battlefield_height - @size * 2
      turn 90 - heading
      return
    end

    if (time % 40) == 0
      @turn_angle = 20 * SecureRandom.random_number - 10
    end
    if (time % 40) < 18
      turn @turn_angle
    else
      @turn_angle = 0
    end
    nearest = scan_for_fire
    if nearest
      if nearest[:latest] == time
        radian = (nearest[:direction] / 180.0 * Math::PI)
        point = {
          x: Math.cos(radian) * nearest[:distance] + x,
          y: -Math.sin(radian) * nearest[:distance] + y
        }
        ticks = (nearest[:distance] / 30) - 1
        if nearest[:point] and gun_heat == 0
          nx = (point[:x] - nearest[:point][:x]) / (time - @last_nearest) * ticks + point[:x]
          ny = (point[:y] - nearest[:point][:y]) / (time - @last_nearest) * ticks + point[:y]
          nangle = ((Math.atan2((ny - y), (x - nx)) - Math::PI) * 180.0 / Math::PI + 360) % 360
          diff = (nangle - gun_heading) % 360
          diff -= 360 if diff > 180
          diff += 360 if diff < -180
          turn_gun (diff - @turn_angle)
          if (diff - @turn_angle).abs <= 30
            @will_fire = true
          end
        end
      end
      @last_nearest = nearest[:latest]
      nearest[:point] = point
    end
  end
end
