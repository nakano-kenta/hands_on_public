require 'rrobots'
class Watanabe
  include Robot

  MAX_RADAR_TURN         = 60
  MAX_GUN_TURN           = 30
  MAX_TURN               = 10
  DANGER_POINT_THRESHOLD = 200
  BULLET_SPPED           = 30
  SAFETY_DISTANCE        = 300

  def initialize
    @target_info= []
    @accelerate_value = 0
    @pattern = nil
    @turn_radar_value = MAX_RADAR_TURN
    @turn_value = 0
    @run_duration = 0
    @will_fire = false
  end

  def reset
  end

  def present_point
    { x: x, y: y }
  end

  def target_last
    @target_info.last
  end

  def future_point
    calc_point(present_point, speed + @accelerate_value, heading + @turn_value)
  end

  def calc_point(base_point, distance, direction)
    {
      x: base_point[:x] + (Math::cos(direction.to_rad) * distance),
      y: base_point[:y] + (- Math::sin(direction.to_rad) * distance)
    }
  end

  def calc_distance(a, b)
    Math.hypot(a[:x] - b[:x], a[:y] - b[:y])
  end

  def center_point_of_circle
    x1 = @target_info[-3][:point][:x]
    x2 = @target_info[-2][:point][:x]
    x3 = @target_info[-1][:point][:x]
    y1 = @target_info[-3][:point][:y]
    y2 = @target_info[-2][:point][:y]
    y3 = @target_info[-1][:point][:y]
    d = (y2*x1 - y1*x2 + y3*x2 - y2*x3 + y1*x3 - y3*x1);
    x = ((x1*x1 + y1*y1) * (y2-y3) + (x2*x2 + y2*y2) * (y3-y1) + (x3*x3 + y3*y3) * (y1-y2)) / (2*d);
    y = -((x1*x1 + y1*y1) * (x2-x3) + (x2*x2 + y2*y2) * (x3-x1) + (x3*x3+y3*y3) * (x1-x2)) / (2*d);

    if x.finite? || y.finite?
      {x: x, y: y}
    else
      nil
    end
  end

  def diff_energy
    @target_info[-2][:energy] - target_last[:energy]
  end

  def to_degree(radian)
    (radian * 180.0 / Math::PI + 360) % 360
  end

  def angle(a, b)
    to_degree(Math::atan2(b[:y] - a[:y], a[:x] - b[:x]) - Math::PI)
  end

  def adjust_direction(angle)
    angle = angle % 360
    if angle > 180
      angle -= 360
    elsif angle < -180
      angle += 360
    end
    angle
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

  def decide_pattern
    if @target_info.size >= 5 && @target_info.last(3).select{
        |info| !info[:center_point_of_circle].nil? && !target_last[:center_point_of_circle].nil? && info[:center_point_of_circle][:x].round == target_last[:center_point_of_circle][:x].round && info[:center_point_of_circle][:y].round == target_last[:center_point_of_circle][:y].round }.size > 2
      @pattern = :circle
    else
      @pattern = :straight
    end
  end

  def search_target
    unless events['robot_scanned'].empty?
      @target_info << events['robot_scanned'].first
      @target_info.last[:time] = time
      @target_info.last[:point] = calc_point(present_point, @target_info.last[:distance], @target_info.last[:direction])

      if @target_info.size >= 2
        t = target_last[:time] - @target_info[-2][:time]
        @target_info.last[:x_velocity] = (target_last[:point][:x] - @target_info[-2][:point][:x]) / t
        @target_info.last[:y_velocity] = (target_last[:point][:y] - @target_info[-2][:point][:y]) / t
        @target_info.last[:velocity]   = calc_distance(@target_info[-2][:point], target_last[:point]) / t
        @target_info.last[:heading]    = angle(@target_info[-2][:point], @target_info.last[:point])
        if @target_info.size >= 3
          @target_info.last[:x_acceleration] = @target_info[-2][:x_velocity] - @target_info.last[:x_velocity] / t
          @target_info.last[:y_acceleration] = @target_info[-2][:y_velocity] - @target_info.last[:y_velocity] / t
          @target_info.last[:acceleration] = (target_last[:velocity] - @target_info[-2][:velocity]) / t
          @target_info.last[:angle_velocity] = adjust_direction(@target_info.last[:heading] - @target_info[-2][:heading]) / t
          @target_info.last[:center_point_of_circle] = center_point_of_circle
          @target_info.last[:radius] = calc_distance(target_last[:point], target_last[:center_point_of_circle]) unless target_last[:center_point_of_circle].nil?
        end
      end
      @turn_radar_value *= -1
    end
    turn_radar @turn_radar_value
  end

  def move
    if dangerous_area?
      @accelerate_value = -1
      @turn_value = adjust_direction(center_direction - heading)
    elsif @target_info.size >= 2 && @target_info.last[:distance] < SAFETY_DISTANCE
      @accelerate_value = -1
      diff_direction = angle(present_point, target_last[:point]) - heading
      @turn_value    = adjust_direction(diff_direction)
    elsif @target_info.size >= 2 && was_shot?
      @accelerate_value = [-1, 1].sample
      diff_direction = angle(present_point, target_last[:point]) - heading
      direction = adjust_direction(diff_direction)
      if 90 > direction.abs
        if direction > 0
          @turn_value = MAX_TURN
        else
          @turn_value = -MAX_TURN
        end
      end
      @turn_value = [MAX_TURN, -MAX_TURN].sample
    elsif @target_info.size >= 2
      diff_direction = angle(present_point, target_last[:point]) - heading
      direction = adjust_direction(diff_direction)
      if 90 > direction.abs
        if direction > 0
          @turn_value = MAX_TURN
        else
          @turn_value = -MAX_TURN
        end
      end
      @turn_value = [MAX_TURN, -MAX_TURN].sample
    else
      @accelerate_value = 1
      @turn_value = [MAX_TURN, -MAX_TURN].sample
    end

    if @turn_value > MAX_TURN
      @turn_value = MAX_TURN
    elsif @turn_value < -MAX_TURN
      @turn_value = -MAX_TURN
    end
  end

  def set_aim
    return turn_gun MAX_GUN_TURN if @target_info.empty?
    return if @target_info.size < 3
    diff_angle = 0
    decide_pattern
    (1..100).each do |tick|
      target_future_point = case @pattern
                            when :circle
                              calc_point(target_last[:center_point_of_circle], target_last[:radius], adjust_direction(target_last[:angle_velocity] * tick + (target_last[:heading]) - 90))
                            when :straight
                              { x: target_last[:point][:x] + target_last[:x_velocity] * tick, y: target_last[:point][:y] + target_last[:y_velocity] * tick }
                            end
      diff_angle = adjust_direction(angle(present_point, target_future_point) - gun_heading)
      break if diff_angle.abs > MAX_GUN_TURN
      distance = calc_distance(target_future_point, present_point)
      break if distance - (BULLET_SPPED * tick) < 10
    end
    case diff_angle
    when diff_angle > MAX_GUN_TURN
      turn_gun MAX_GUN_TURN
    when diff_angle < -MAX_GUN_TURN
      turn_gun -MAX_GUN_TURN
    else
      turn_gun diff_angle - @turn_value
      @will_fire = true
    end
  end

  def attack
    if !@target_info.empty? && @target_info.last[:energy] < 0.5
      @accelerate_value = 1
      diff_direction = angle(present_point, target_last[:point]) - heading
      @turn_value    = adjust_direction(diff_direction)
      @will_fire = false
    end

    if @will_fire
      if @target_info.last[:distance] < 500
        fire 3
      elsif @target_info.last[:distance] > 500 && @target_info.last[:distance] < 1000
        fire 2
      else
        fire 0.3
      end

      @will_fire = false
    end
  end

  def tick(events)
    return if num_robots == 1
    reset
    search_target
    set_aim
    move
    attack
    turn @turn_value
    accelerate @accelerate_value
  end
end
