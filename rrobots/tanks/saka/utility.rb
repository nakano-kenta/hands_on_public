require 'rrobots'

module SakaUtil
  module Constants
    MAX_HISTORIES = 100
    MAX_FIRE = 3
    BULLET_SPEED = 30
    MAX_GUN_ROTATE = 30
    MAX_RADAR_ROTATE = 60
    MAX_BODY_ROTATE = 10
    MAX_SPEED = 8
  end
  module Utility
    private

    def to_angle(radian)
      to_positive_direction radian * 180.0 / Math::PI
    end

    def to_positive_direction(direction)
      direction = direction + ((-direction / 360).to_i + 1) * 360 if direction < 0
      direction % 360
    end

    def to_min_direction(direction)
      direction = to_positive_direction(direction)
      direction <= 180 ? direction : direction - 360
    end

    def to_direction(a, b)
      diff_x = a[:x] - b[:x]
      diff_y = b[:y] - a[:y]
      to_angle(Math.atan2(diff_y, diff_x) - Math::PI)
    end

    def to_distance(a, b)
      Math::hypot(a[:x] - b[:x], b[:y] - a[:y])
    end
    def trace(message)
      method_name = caller_locations(1,1)[0].label
      puts "#{method_name}: #{message}"
    end
    def debug_draw_point(x, y, size, color = 0xffffff00)
      scale = 0.5
      x *= scale
      y *= scale
      size *= scale
      Gosu.draw_rect(x - size / 2, y - size/ 2, size, size, color, ZOrder::UI + 1)
    end
    def debug_draw_point_by_degree(src, degree, distance, size, color = 0xffffff00)
      x = src.is_a?(Robot) ? src.x : src[:x]
      y = src.is_a?(Robot) ? src.y : src[:y]
      degree_rad = degree.to_rad
      debug_draw_point Math::cos(degree_rad) * distance + x, -Math::sin(degree_rad) * distance + y, size, color
    end

    def nearest_direction(direction, base_direction)
      nearest = direction
      nearest_diff = (direction - base_direction).abs
      return direction if nearest_diff.abs < 180

      direction = to_positive_direction(direction) + (base_direction / 360).to_i * 360
      nearest_diff = (direction - base_direction).abs
      (-2..2).each do |mul|
        alt = direction + mul * 360
        diff = (alt - base_direction).abs
        if diff < nearest_diff
          nearest = alt
          nearest_diff = diff
        end
      end
      nearest
    end
  end
end