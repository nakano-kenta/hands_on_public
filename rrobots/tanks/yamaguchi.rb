require 'rrobots'
require 'matrix'

class Yamaguchi
  include Robot

  BULLET_SPEED = 30

  def tick(events)
    @log_by_robo = {} if time == 0
    @aim = [] if time == 0
    search_enemies
    set_run_params
    set_aim
    attack
    turn @turn_direction
    accelerate @acceleration
    turn_gun @turn_gun_direction
  end

  def search_enemies
    @scan_direction ||= 60
    @turn_gun_direction ||= 30
    unless events['robot_scanned'].empty?
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
          @log_by_robo[robot_scanned[:name]].last[:heading] = Math::acos(@log_by_robo[robot_scanned[:name]].last[:x_speed] / @log_by_robo[robot_scanned[:name]].last[:speed]) * 180 / Math::PI if @log_by_robo[robot_scanned[:name]].last[:speed] > 0
          if @log_by_robo[robot_scanned[:name]].size > 2
            @log_by_robo[robot_scanned[:name]].last[:x_acceleration] = 2 / t ** 2 * ( (@log_by_robo[robot_scanned[:name]].last[:x] - @log_by_robo[robot_scanned[:name]][-2][:x]) - (@log_by_robo[robot_scanned[:name]][-2][:x_speed].to_i * t) )
            @log_by_robo[robot_scanned[:name]].last[:y_acceleration] = 2 / t ** 2 * ( (@log_by_robo[robot_scanned[:name]][-2][:y] - @log_by_robo[robot_scanned[:name]].last[:y]) - (@log_by_robo[robot_scanned[:name]][-2][:y_speed].to_i * t) )
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
      @scan_direction *= -1
      @turn_gun_direction *= -1
    end
    turn_radar @scan_direction
  end

  def set_run_params
    @turn_direction ||= 0
    @acceleration ||= 1
    @progress_direction ||= 1
    return if @log_by_robo.empty?
    recent_logs = @log_by_robo.map { |name, logs| (time - logs.last[:time]) < 10 ? logs.last : nil }.compact
    return if recent_logs.empty?
    recent_logs.each do |log|
      hit_bonus = 0
      next if log.size < 10
      got_hit = events['got_hit'].select {|aa| aa[:from] == log[:name]}.first
      hit_bonus = got_hit[:damage] * 2/3 if got_hit
      @duration += 10 if (0.1..3).cover? @log_by_robo[log[:name]][-2][:energy] - log[:energy] + hit_bonus
    end
    close_enemy = recent_logs.min_by { |log| log[:distance] }
    counter_angle = 90
    near_enemy = ( 1000 > close_enemy[:distance] ? 1 : -1 )
    near_enemy *= @progress_direction
    counter_angle += (20 * near_enemy)
    counter_angle = 0 if close_enemy[:energy] < 1 and @log_by_robo[close_enemy[:name]][-10][:energy] < 1
    direction = diff_direction( {x: x, y: (battlefield_height - y)}, {x: close_enemy[:x], y: close_enemy[:y]} ) - heading - counter_angle
    direction += 360 if direction < 0
    direction -= 360 if direction > 180
    @turn_direction = direction
    @acceleration = @progress_direction
    @acceleration = 1 if close_enemy[:energy] < 1 and @log_by_robo[close_enemy[:name]][-10][:energy] < 1
    @progress_direction *= -1 unless events[:crash_into_wall].empty?
    @progress_direction *= -1 unless events[:crash_into_enemy].empty?
    @duration ||= 0
    if time - @duration > 0
      @progress_direction *= -1
      @duration = time + 10
    end
  end

  def set_aim
    @singular_points = {}
    @log_by_robo.each do |name, robo_log|
      next if robo_log.size < 4
      @singular_points[name] = robo_log.select do |log|
        log[:x].round == robo_log.last[:x].round and log[:y].round == robo_log.last[:y].round and log[:x_speed]&.round == robo_log.last[:x_speed]&.round and log[:y_speed]&.round == robo_log.last[:y_speed]&.round and !(log[:x_speed].round == 0 and log[:y_speed].round == 0)
      end
    end
    @singular_points.each do |name, singular_point|
      next if singular_point.size < 2
      @aim << {
        name: name,
        time: time,
        hit_time: time + (singular_point.last[:time] - singular_point[-2][:time]),
        x: singular_point.last[:x],
        y: singular_point.last[:y]
      }
    end
    target = @log_by_robo.map { |name, logs| time == logs.last[:time] ? logs.last : nil }.compact.min_by { |log| log[:distance] }
    return if !target or @log_by_robo[target[:name]].size < 4
    robo_log = @log_by_robo[target[:name]]
    time_to_be_hit = 30 + robo_log.last[:distance] / BULLET_SPEED
    nextx = robo_log.last[:x] + (robo_log.last[:x_speed] * time_to_be_hit) + (0.5 * robo_log.last[:x_acceleration] * time_to_be_hit ** 2)
    nexty = robo_log.last[:y] + (robo_log.last[:y_speed] * time_to_be_hit) + (0.5 * robo_log.last[:y_acceleration] * time_to_be_hit ** 2)
    if robo_log.last[:radius] and robo_log[-2][:radius] and (robo_log.last[:radius] - robo_log[-2][:radius]).abs < 100
      nextx = robo_log.last[:x] + robo_log.last[:radius] * Math.cos(robo_log.last[:angle_to_circle].to_rad + robo_log.last[:angular_speed].to_rad * time_to_be_hit) - robo_log.last[:radius] * Math.cos(robo_log.last[:angle_to_circle].to_rad)
      nexty = robo_log.last[:y] + robo_log.last[:radius] * Math.sin(robo_log.last[:angle_to_circle].to_rad + robo_log.last[:angular_speed].to_rad * time_to_be_hit) - robo_log.last[:radius] * Math.sin(robo_log.last[:angle_to_circle].to_rad)
    end
    @aim << {
      name: target[:name],
      time: time,
      hit_time: time + time_to_be_hit,
      x: nextx,
      y: nexty
    }
  end

  def attack
    @aim.delete_if { |aim| 10 < time - aim[:time] }
    @next_aim ||= @aim.first
    return unless @next_aim
    x_future = x + speed * Math::cos(heading.to_rad)
    y_future = (battlefield_height - y) + speed * Math::sin(heading.to_rad)
    turn_gun_direction = diff_direction( {x: x_future, y: y_future}, {x: @next_aim[:x], y: @next_aim[:y]} )
    turn_gun_direction -= gun_heading + @turn_direction
    @turn_gun_direction = turn_gun_direction

    bullet_duration = Math::hypot(x_future - @next_aim[:x], y_future - @next_aim[:y]) / BULLET_SPEED
    if @next_aim[:hit_time] - (time + bullet_duration) < -2
      @next_aim = nil
    else
      if turn_gun_direction.abs <= 30 and @next_aim[:hit_time] - (time + bullet_duration) < 1
        forecast_x = @log_by_robo[@next_aim[:name]].last[:x] + (@log_by_robo[@next_aim[:name]].last[:x_speed] * bullet_duration) + (0.5 * @log_by_robo[@next_aim[:name]].last[:x_acceleration] * bullet_duration ** 2)
        forecast_y = @log_by_robo[@next_aim[:name]].last[:y] + (@log_by_robo[@next_aim[:name]].last[:y_speed] * bullet_duration) + (0.5 * @log_by_robo[@next_aim[:name]].last[:y_acceleration] * bullet_duration ** 2)
        if @log_by_robo[@next_aim[:name]].last[:radius] and @log_by_robo[@next_aim[:name]][-2][:radius] and (@log_by_robo[@next_aim[:name]].last[:radius] - @log_by_robo[@next_aim[:name]][-2][:radius]).abs < 100
          forecast_x = @log_by_robo[@next_aim[:name]].last[:x] + @log_by_robo[@next_aim[:name]].last[:radius] * Math.cos(@log_by_robo[@next_aim[:name]].last[:angle_to_circle].to_rad + @log_by_robo[@next_aim[:name]].last[:angular_speed].to_rad * bullet_duration) - @log_by_robo[@next_aim[:name]].last[:radius] * Math.cos(@log_by_robo[@next_aim[:name]].last[:angle_to_circle].to_rad)
          forecast_y = @log_by_robo[@next_aim[:name]].last[:y] + @log_by_robo[@next_aim[:name]].last[:radius] * Math.sin(@log_by_robo[@next_aim[:name]].last[:angle_to_circle].to_rad + @log_by_robo[@next_aim[:name]].last[:angular_speed].to_rad * bullet_duration) - @log_by_robo[@next_aim[:name]].last[:radius] * Math.sin(@log_by_robo[@next_aim[:name]].last[:angle_to_circle].to_rad)
        end
        fire (@log_by_robo[@next_aim[:name]].last[:energy] > 20 ? 3 : @log_by_robo[@next_aim[:name]].last[:energy]/3.3 - 0.5)
        @next_aim = nil
      end
    end
  end

  def diff_direction(observation, target)
    direction = Math::atan( (target[:y] - observation[:y]) / (target[:x] - observation[:x]) ) * 180 / Math::PI
    direction += 180 if (target[:x] - observation[:x]) < 0
    direction += 360 if direction < 0
    direction
  end
end
