require 'rrobots'
require 'matrix'

class Yamaguchi
  include Robot

  BULLET_SPEED = 30
  MAX_ANGLE_OF_RADAR = 60
  MAX_ANGLE_OF_RUN = 30
  MAX_ROBO_SPEED = 8
  MIN_ROBO_SPEED = -8

  AWAY_THRESHOLD = 400
  ABOID_WALL_THRESHOLD = 92

  def tick(events)
    @log_by_robo = {} if time == 0
    @targets = [] if time == 0
    search_enemies
    set_run_params
    set_aim
    attack
    turn @turn_direction
    turn_gun @turn_gun_direction
    turn_radar @scan_direction
    accelerate @acceleration
  end

  def search_enemies
    @scan_direction ||= MAX_ANGLE_OF_RADAR
    @turn_gun_direction ||= MAX_ANGLE_OF_RUN
    if events['robot_scanned'].empty?
      @scan_direction = (0 < @scan_direction ? 1 : -1) * MAX_ANGLE_OF_RADAR
    else
      events['robot_scanned'].each do |robot_scanned|
        @log_by_robo[robot_scanned[:name]] ||=  []
        @log_by_robo[robot_scanned[:name]] << robot_scanned
        @log_by_robo[robot_scanned[:name]].last[:time] = time
        @log_by_robo[robot_scanned[:name]].last[:x] = x + Math::cos(@log_by_robo[robot_scanned[:name]].last[:direction].to_rad) * @log_by_robo[robot_scanned[:name]].last[:distance]
        @log_by_robo[robot_scanned[:name]].last[:y] = battlefield_height - (y - Math::sin(@log_by_robo[robot_scanned[:name]].last[:direction].to_rad) * @log_by_robo[robot_scanned[:name]].last[:distance])
        if @log_by_robo[robot_scanned[:name]].size > 1
          t = @log_by_robo[robot_scanned[:name]].last[:time] - @log_by_robo[robot_scanned[:name]][-2][:time]
          @log_by_robo[robot_scanned[:name]].last[:x_speed] = (@log_by_robo[robot_scanned[:name]].last[:x] - @log_by_robo[robot_scanned[:name]][-2][:x]) / t
          @log_by_robo[robot_scanned[:name]].last[:y_speed] = (@log_by_robo[robot_scanned[:name]].last[:y] - @log_by_robo[robot_scanned[:name]][-2][:y]) / t
          @log_by_robo[robot_scanned[:name]].last[:speed] = Math::hypot(@log_by_robo[robot_scanned[:name]].last[:x_speed], @log_by_robo[robot_scanned[:name]].last[:y_speed])
          @log_by_robo[robot_scanned[:name]].last[:heading] = to_angle(Math::acos(@log_by_robo[robot_scanned[:name]].last[:x_speed] / @log_by_robo[robot_scanned[:name]].last[:speed])) if @log_by_robo[robot_scanned[:name]].last[:speed] > 0
          if @log_by_robo[robot_scanned[:name]].size > 2
            @log_by_robo[robot_scanned[:name]].last[:x_acceleration] = (2 * ((@log_by_robo[robot_scanned[:name]].last[:x] - @log_by_robo[robot_scanned[:name]][-2][:x]) - @log_by_robo[robot_scanned[:name]][-2][:x_speed] * t) / t ** 2 ).round
            @log_by_robo[robot_scanned[:name]].last[:x_acceleration] = round_whithin_range(@log_by_robo[robot_scanned[:name]].last[:x_acceleration], -1..1)
            @log_by_robo[robot_scanned[:name]].last[:y_acceleration] = (2 * ((@log_by_robo[robot_scanned[:name]].last[:y] - @log_by_robo[robot_scanned[:name]][-2][:y]) - @log_by_robo[robot_scanned[:name]][-2][:y_speed] * t) / t ** 2 ).round
            @log_by_robo[robot_scanned[:name]].last[:y_acceleration] = round_whithin_range(@log_by_robo[robot_scanned[:name]].last[:y_acceleration], -1..1)
            if @log_by_robo[robot_scanned[:name]].last[:heading] and @log_by_robo[robot_scanned[:name]][-2][:heading]
              @log_by_robo[robot_scanned[:name]].last[:angular_speed] = (@log_by_robo[robot_scanned[:name]].last[:heading] - @log_by_robo[robot_scanned[:name]][-2][:heading]) / t
              if  @log_by_robo[robot_scanned[:name]].last[:angular_speed].abs > 2
                @log_by_robo[robot_scanned[:name]].last[:radius] = (@log_by_robo[robot_scanned[:name]].last[:speed] / @log_by_robo[robot_scanned[:name]].last[:angular_speed].to_rad).abs.round
                @log_by_robo[robot_scanned[:name]].last[:angle_to_circle] = @log_by_robo[robot_scanned[:name]].last[:heading] - (@log_by_robo[robot_scanned[:name]].last[:angular_speed] > 0 ? 90 : 270 )
                @log_by_robo[robot_scanned[:name]].last[:angle_to_circle] += 360 if @log_by_robo[robot_scanned[:name]].last[:angle_to_circle] < 0
              end
            end
          end
        end
      end
      diff_radar_direction = events['robot_scanned'].min_by { |log| log[:distance] }[:direction] - radar_heading
      @scan_direction = optimize_angle(diff_radar_direction) * 2
    end
    @scan_direction = MAX_ANGLE_OF_RADAR if num_robots > 2 and (54..59).cover?(time % 60)
  end

  def set_run_params
    @turn_direction ||= 0
    @acceleration ||= 1
    @progress_direction ||= 1
    @enemy_stop_at ||= {}
    @log_by_robo.delete_if { |name, logs| 300 < time - logs.last[:time] }
    return if @log_by_robo.empty?
    recent_logs = @log_by_robo.map { |name, logs| (time - logs.last[:time]) < 10 ? logs.last : nil }.compact
    return if recent_logs.empty?
    recent_logs.each do |log|
      hit_bonus = 0
      next if log.size < 10
      got_hit = events['got_hit'].select {|hit_log| hit_log[:from] == log[:name]}.first
      hit_bonus = got_hit[:damage] * 2/3 if got_hit
      @duration += 10 if @duration - time < 20 and  (0.1..3).cover? @log_by_robo[log[:name]][-2][:energy] - log[:energy] + hit_bonus
    end
    close_enemy = recent_logs.min_by { |log| log[:distance] }
    counter_angle = 90
    near_enemy = ( 800 > close_enemy[:distance] ? 1 : -1 )
    near_enemy *= @progress_direction
    counter_angle += (20 * near_enemy)
    @enemy_stop_at[close_enemy[:name]] ||= time if close_enemy[:energy] < 1
    counter_angle = 0 if @enemy_stop_at[close_enemy[:name]] and time - @enemy_stop_at[close_enemy[:name]] > 50 and @log_by_robo[close_enemy[:name]][-10] and @log_by_robo[close_enemy[:name]][-10][:energy] < 1
    direction = diff_direction( {x: x, y: (battlefield_height - y)}, {x: close_enemy[:x], y: close_enemy[:y]} ) - heading - counter_angle
    @turn_direction = optimize_angle(direction)
    @acceleration = @progress_direction
    @acceleration = 1 if close_enemy[:energy] < 1 and @log_by_robo[close_enemy[:name]][-10] and @log_by_robo[close_enemy[:name]][-10][:energy] < 1
    @progress_direction *= -1 unless events[:crash_into_wall].empty?

    if Math::hypot(x - close_enemy[:x], (battlefield_height - y) - close_enemy[:y]) < AWAY_THRESHOLD and close_enemy[:energy] > 1 and close_enemy[:heading]
      @turn_direction = diff_direction( {x: x, y: (battlefield_height - y)}, {x: close_enemy[:x], y: close_enemy[:y]} ) - heading
      if x < ABOID_WALL_THRESHOLD or x > battlefield_height - ABOID_WALL_THRESHOLD or y < ABOID_WALL_THRESHOLD or y > battlefield_height - ABOID_WALL_THRESHOLD
        @acceleration = 1
      else
        @acceleration = -1
      end
      turn_gun_direction = diff_direction( {x: x, y: (battlefield_height - y)}, {x: close_enemy[:x], y: close_enemy[:y]} ) - gun_heading
      turn_gun_direction = optimize_angle(turn_gun_direction)
      turn_gun_direction += (turn_gun_direction * @turn_direction > 1 ? @turn_direction : -@turn_direction)
      @turn_gun_direction = turn_gun_direction
      @duration = time
      @brain_muscle = true
      return
    end

    @duration ||= 0
    if time - @duration > 0
      @progress_direction *= -1
      @duration = time + 10
    end
  end

  def set_aim
    if @brain_muscle
      fire 3 if @turn_gun_direction.abs <= 30
      @brain_muscle = false
      return
    end
    @singular_points = {}
    @log_by_robo.each do |name, robo_log|
      next if robo_log.size < 4
      @singular_points[name] = robo_log.select do |log|
        log[:x].round == robo_log.last[:x].round and log[:y].round == robo_log.last[:y].round and log[:x_speed]&.round == robo_log.last[:x_speed]&.round and log[:y_speed]&.round == robo_log.last[:y_speed]&.round and !(log[:x_speed].round == 0 and log[:y_speed].round == 0)
      end
    end
    @singular_points.each do |name, singular_point|
      next if singular_point.size < 2
      @targets << {
        name: name,
        time: time,
        hit_time: time + (singular_point.last[:time] - singular_point[-2][:time]),
        x: singular_point.last[:x],
        y: singular_point.last[:y],
        singular: true
      }
      return
    end
    target = @log_by_robo.map { |name, logs| time == logs.last[:time] ? logs.last : nil }.compact.min_by { |log| log[:distance] }
    return if !target or @log_by_robo[target[:name]].size < 4
    robo_log = @log_by_robo[target[:name]]
    time_to_be_hit = 25 + robo_log.last[:distance] / BULLET_SPEED
    nextx = calc_spot(robo_log.last[:x], robo_log.last[:x_speed], robo_log.last[:x_acceleration], time_to_be_hit)
    nexty = calc_spot(robo_log.last[:y], robo_log.last[:y_speed], robo_log.last[:y_acceleration], time_to_be_hit)
    if robo_log.last[:radius] and robo_log[-2][:radius] and (robo_log.last[:radius] - robo_log[-2][:radius]).abs < 100
      nextx = robo_log.last[:x] + robo_log.last[:radius] * Math.cos(robo_log.last[:angle_to_circle].to_rad + robo_log.last[:angular_speed].to_rad * time_to_be_hit) - robo_log.last[:radius] * Math.cos(robo_log.last[:angle_to_circle].to_rad)
      nexty = robo_log.last[:y] + robo_log.last[:radius] * Math.sin(robo_log.last[:angle_to_circle].to_rad + robo_log.last[:angular_speed].to_rad * time_to_be_hit) - robo_log.last[:radius] * Math.sin(robo_log.last[:angle_to_circle].to_rad)
    end
    return if 0 > nextx or battlefield_height < nextx or 0 > nexty or battlefield_width < nexty
    @targets << {
      name: target[:name],
      time: time,
      hit_time: time + time_to_be_hit,
      x: nextx,
      y: nexty,
      x_acceleration: robo_log.last[:x_acceleration],
      y_acceleration: robo_log.last[:y_acceleration],
    }
  end

  def attack
    @targets.delete_if { |target| !@log_by_robo.keys.include?(target[:name]) }
    @next_aim = nil if @next_aim and !@log_by_robo.keys.include?(@next_aim[:name])
    @next_aim ||= @targets.last unless @targets.empty?
    return unless @next_aim
    if !@next_aim[:singular] and \
      (@next_aim[:x_acceleration] * @log_by_robo[@next_aim[:name]].last[:x_acceleration] < 0 or \
       @next_aim[:y_acceleration] * @log_by_robo[@next_aim[:name]].last[:y_acceleration] < 0 or \
       (@next_aim[:x_acceleration] + @log_by_robo[@next_aim[:name]].last[:x_acceleration] != 0 and @next_aim[:x_acceleration] * @log_by_robo[@next_aim[:name]].last[:x_acceleration] == 0) or \
       (@next_aim[:y_acceleration] + @log_by_robo[@next_aim[:name]].last[:y_acceleration] != 0 and @next_aim[:y_acceleration] * @log_by_robo[@next_aim[:name]].last[:y_acceleration] == 0)
      )
      @next_aim = nil
      return
    end
    x_future = x + speed * Math::cos(heading.to_rad)
    y_future = (battlefield_height - y) + speed * Math::sin(heading.to_rad)
    turn_gun_direction = diff_direction( {x: x_future, y: y_future}, {x: @next_aim[:x], y: @next_aim[:y]} ) - gun_heading
    turn_gun_direction = optimize_angle(turn_gun_direction)
    turn_gun_direction += (turn_gun_direction * @turn_direction > 1 ? @turn_direction : -@turn_direction)
    @turn_gun_direction = turn_gun_direction
    bullet_duration = Math::hypot(x_future - @next_aim[:x], y_future - @next_aim[:y]) / BULLET_SPEED
    if @next_aim[:hit_time] - (time + bullet_duration) < -2
      @next_aim = nil
    else
      if turn_gun_direction.abs <= 30 and @next_aim[:hit_time] - (time + bullet_duration) < 1
        forecast_x = calc_spot(@log_by_robo[@next_aim[:name]].last[:x], @log_by_robo[@next_aim[:name]].last[:x_speed], @log_by_robo[@next_aim[:name]].last[:x_acceleration], bullet_duration)
        forecast_y = calc_spot(@log_by_robo[@next_aim[:name]].last[:y], @log_by_robo[@next_aim[:name]].last[:y_speed], @log_by_robo[@next_aim[:name]].last[:y_acceleration], bullet_duration)
        if @log_by_robo[@next_aim[:name]].last[:radius] and @log_by_robo[@next_aim[:name]][-2][:radius] and (@log_by_robo[@next_aim[:name]].last[:radius] - @log_by_robo[@next_aim[:name]][-2][:radius]).abs < 100
          forecast_x = @log_by_robo[@next_aim[:name]].last[:x] + @log_by_robo[@next_aim[:name]].last[:radius] * Math.cos(@log_by_robo[@next_aim[:name]].last[:angle_to_circle].to_rad + @log_by_robo[@next_aim[:name]].last[:angular_speed].to_rad * bullet_duration) - @log_by_robo[@next_aim[:name]].last[:radius] * Math.cos(@log_by_robo[@next_aim[:name]].last[:angle_to_circle].to_rad)
          forecast_y = @log_by_robo[@next_aim[:name]].last[:y] + @log_by_robo[@next_aim[:name]].last[:radius] * Math.sin(@log_by_robo[@next_aim[:name]].last[:angle_to_circle].to_rad + @log_by_robo[@next_aim[:name]].last[:angular_speed].to_rad * bullet_duration) - @log_by_robo[@next_aim[:name]].last[:radius] * Math.sin(@log_by_robo[@next_aim[:name]].last[:angle_to_circle].to_rad)
        end
        fire (@log_by_robo[@next_aim[:name]].last[:energy] > 20 ? 3 : @log_by_robo[@next_aim[:name]].last[:energy]/3.3 - 0.5) if num_robots > 1 and (@next_aim[:singular] or ((forecast_x - @next_aim[:x]).abs < 100 and (forecast_y - @next_aim[:y]).abs < 100))
        @next_aim = nil
      end
    end
  end

  def diff_direction(observation, target)
    direction = to_angle(Math::atan( (target[:y] - observation[:y]) / (target[:x] - observation[:x]) ))
    direction += 180 if (target[:x] - observation[:x]) < 0
    direction += 360 if direction < 0
    direction
  end

  def to_angle(radian)
    radian * 180 / Math::PI
  end

  def round_whithin_range(value, range)
    return range.first if range.first > value
    return range.last if range.last < value
    value
  end

  def optimize_angle(angle)
    angle += 360 if 0 > angle
    angle -= 360 if 180 < angle
    angle
  end

  def calc_spot(current_point, current_speed, current_acceleration, duration)
    result = current_point + (current_speed * duration)
    if current_acceleration.abs > 0
      acceleration_time = (current_speed * current_acceleration > 0 ? (8 - current_speed.abs)/current_acceleration.abs : (MAX_ROBO_SPEED + current_speed.abs)/current_acceleration.abs)
      result = current_point + (current_speed * acceleration_time) + (0.5 * current_acceleration * acceleration_time ** 2) + ( (0 < current_acceleration ? MAX_ROBO_SPEED : MIN_ROBO_SPEED ) * (duration - acceleration_time))
    end
    result
  end
end
