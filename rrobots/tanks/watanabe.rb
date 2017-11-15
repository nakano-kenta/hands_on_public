require 'rrobots'
class Watanabe
  include Robot

  MAX_RADAR_TURN         = 60
  MAX_GUN_TURN           = 30
  MAX_TURN               = 10
  DANGER_POINT_THRESHOLD = 200
  BULLET_SPPED           = 30

  def initialize
    @target_info= []
    @accelerate_value = 0
    @turn_radar_value = MAX_RADAR_TURN
    @turn_value = 0
  end

  def reset
  end

  def present_point
    { x: x, y: y }
  end

  def future_point
    calc_point(present_point, speed + @accelerate_value, heading + @turn_value)
  end

  def calc_point(base_point, distance, direction)
    {
      x: base_point[:x] + (distance * Math::cos(direction.to_rad)).round,
      y: base_point[:y] + (distance * Math::sin((360 - direction).to_rad)).round
    }
  end

  def diff_energy
    @target_info[-2][:energy] - @target_info.last[:energy]
  end

  def angle(base, target)
    degree = Math::atan2(target[:x] - base[:x], target[:y] - base[:y]) * 180 / Math::PI
    degree = degree + 270
    degree = degree - 360 if degree > 360
    degree
  end

  def was_shot?
    0 < diff_energy && diff_energy <= 3
  end

  def center_direction
    angle({x: battlefield_width / 2, y: battlefield_height / 2}, {x: x, y: y})
  end

  def dangerous_area?
    x < DANGER_POINT_THRESHOLD || x > (battlefield_width - DANGER_POINT_THRESHOLD) || y < DANGER_POINT_THRESHOLD || y > (battlefield_height - DANGER_POINT_THRESHOLD)
  end

  def search_target
    unless events['robot_scanned'].empty?
      @target_info << events['robot_scanned'].first
      @target_info.last[:time] = time
      @target_info.last.merge!(calc_point(present_point, @target_info.last[:distance], @target_info.last[:direction]))
      if @target_info.size >= 2
        t = @target_info[-2][:time] - @target_info.last[:time]
        @target_info.last[:x_velocity] = (@target_info[-2][:x] - @target_info.last[:x]) / t
        @target_info.last[:y_velocity] = (@target_info[-2][:y] - @target_info.last[:y]) / t
        if @target_info.size >= 3
          @target_info.last[:x_acceleration] = @target_info[-2][:x_velocity] - @target_info.last[:x_velocity] / t
          @target_info.last[:y_acceleration] = @target_info[-2][:y_velocity] - @target_info.last[:y_velocity] / t
        end
      end
      @turn_radar_value *= -1
    end
    turn_radar @turn_radar_value
  end

  def move
    @run_duration ||= 0
    if dangerous_area?
      @accelerate_value = -1
      @turn_value = center_direction - heading
    elsif @target_info.size >= 2 && @target_info.last[:distance] < 300
      @accelerate_value = -1
      diff_direction = angle(present_point, {x: @target_info.last[:x], y: @target_info.last[:y]}) - heading
      @turn_value = diff_direction
    elsif @target_info.size >= 2 && was_shot?
      @accelerate_value = -1
      # diff_direction = angle(present_point, {x: @target_info.last[:x], y: @target_info.last[:y]}) - heading
      # @turn_value = diff_direction
    else
      return if @run_duration - time > 0
      @run_duration = rand(50..100)
      @accelerate_value = [-1, -0.9, -0.8, -0.7, 0.7, 0.8, 0.9, 1].sample
      @turn_value = [MAX_TURN, -MAX_TURN].sample
    end
  end

  def set_aim
    return turn_gun MAX_GUN_TURN if @target_info.empty?
    return if @target_info.size < 2
    diff_angle = 0
    (20..100).each do |tick|
      target_future_point = { x: @target_info.last[:x] + @target_info.last[:x_velocity] * tick, y: @target_info.last[:y] + @target_info.last[:y_velocity] * tick }
      diff_angle = angle(present_point, target_future_point) - gun_heading
      break if diff_angle.abs > MAX_GUN_TURN
      distance = Math::hypot(target_future_point[:x] - x, target_future_point[:y] - y)
      break if distance - (BULLET_SPPED * tick) < 10
    end
    # target_future_point = { x: @target_info.last[:x] + @target_info.last[:x_velocity], y: @target_info.last[:y] + @target_info.last[:y_velocity]}
    # diff_angle = angle(present_point, target_future_point) - gun_heading
    case diff_angle
    when diff_angle > MAX_GUN_TURN
      turn_gun MAX_GUN_TURN
    when diff_angle < -MAX_GUN_TURN
      turn_gun -MAX_GUN_TURN
    else
      turn_gun diff_angle - @turn_value
      fire 3 if (diff_angle - @turn_value).abs <= 30
    end
  end


  def tick(events)
    return if game_over
    reset
    search_target
    set_aim
    move
    turn @turn_value
    accelerate @accelerate_value
  end
end
