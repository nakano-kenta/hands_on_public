require 'rrobots'

class Yamaguchi
  include Robot

  ABOID_WALL_THRESHOLD = 92
  AWAY_THRESHOLD = 400

  def tick(events)
    @info = [] if time == 0
    @aim = [] if time == 0
    search_enemies
    set_run_params
    set_aim if @info.size > 3 and !events['robot_scanned'].empty?
    attack
    turn @turn_direction
    accelerate @acceleration
  end

  def search_enemies
    @scan_direction ||= 60
    unless events['robot_scanned'].empty?
      @info << events['robot_scanned'].first
      @info.last[:time] = time
      @info.last[:x] = (x + Math::cos(@info.last[:direction].to_rad) * @info.last[:distance]).round
      @info.last[:y] = (battlefield_height - (y - Math::sin(@info.last[:direction].to_rad) * @info.last[:distance])).round
      if @info.size > 1
        t = @info[-2][:time] - @info.last[:time]
        @info.last[:x_speed] = (@info[-2][:x] - @info.last[:x]) / t
        @info.last[:y_speed] = (@info[-2][:y] - @info.last[:y]) / t
        if @info.size > 2
          @info.last[:x_acceleration] = 2 / t ** 2 * ( (@info.last[:x] - @info[-2][:x]) - (@info[-2][:x_speed].to_i * t) )
          @info.last[:y_acceleration] = 2 / t ** 2 * ( (@info.last[:y] - @info[-2][:y]) - (@info[-2][:y_speed].to_i * t) )
        end
      end
      @scan_direction *= -1
    end
    turn_radar @scan_direction
  end

  def set_run_params
    @run_duration ||= 0
    if @aboiding_wall or  x < ABOID_WALL_THRESHOLD or x > battlefield_height - ABOID_WALL_THRESHOLD or y < ABOID_WALL_THRESHOLD or y > battlefield_height - ABOID_WALL_THRESHOLD
      center_direction = diff_direction( {x: battlefield_width / 2, y: battlefield_height / 2}, {x: x, y: battlefield_height - y} )
      @turn_direction = center_direction - heading
      @acceleration = -1
      @aboiding_wall = (x < ABOID_WALL_THRESHOLD + 100 or x > battlefield_height - ABOID_WALL_THRESHOLD - 100 or y < ABOID_WALL_THRESHOLD + 100 or y > battlefield_height - ABOID_WALL_THRESHOLD - 100 ? true : false)
    elsif @info.size > 0 and Math::hypot(x - @info.last[:x], (battlefield_height - y) - @info.last[:y]) < AWAY_THRESHOLD
      @turn_direction = diff_direction( {x: x, y: (battlefield_height - y)}, {x: @info.last[:x], y: @info.last[:y]} ) - heading
      @acceleration = -1
      @run_duration = 10
    else
      return if @run_duration - time > 0
      @run_duration = time + rand(200) + 20
      @turn_direction = rand(-9..10)
      @acceleration = rand + 0.2
    end
  end

  def set_aim
    singular_point = @info.select do |info|
      info[:x] == @info.last[:x] and info[:y] == @info.last[:y] and info[:x_speed] == @info.last[:x_speed] and info[:y_speed] == @info.last[:y_speed] and info[:x_speed] != 0
    end
    if singular_point.size > 1
      @aim << {
        time: time + (singular_point.last[:time] - singular_point[-2][:time]),
        x: singular_point.last[:x],
        y: singular_point.last[:y]
      }
    elsif (@info.last[:x_acceleration] * @info[-2][:x_acceleration] >= 0) and (@info.last[:y_acceleration] * @info[-2][:y_acceleration] >= 0)
      time_to_be_hit = 15 + @info.last[:distance] * 0.05
      @aim << {
        time: time + time_to_be_hit,
        x: @info.last[:x] + (@info.last[:x_speed] * time_to_be_hit) + (0.5 * @info.last[:x_acceleration] * time_to_be_hit ** 2),
        y: @info.last[:y] + (@info.last[:y_speed] * time_to_be_hit) + (0.5 * @info.last[:y_acceleration] * time_to_be_hit ** 2)
      }
    end
  end

  def attack
    @aim.delete_if { |aim| 30 > aim[:time] - time }
    @next_aim ||= @aim.select { |aim| (30 < aim[:time] - time) }.sort { |a, b| a[:time] <=> b[:time] }.first
    return unless @next_aim
    x_future = x + speed * Math::cos(heading.to_rad)
    y_future = y - speed * Math::sin(heading.to_rad)
    direction = diff_direction( {x: x_future, y: (battlefield_height - y_future)}, {x: @next_aim[:x], y: @next_aim[:y]} )
    direction -= gun_heading + @turn_direction
    turn_gun direction
    bullet_duration = Math::hypot(x_future - @next_aim[:x], (battlefield_height - y_future) - @next_aim[:y]) / 30
    if @next_aim[:time] - (time + bullet_duration) < -2
      @next_aim = nil
    else
      if direction.abs < 11 and @next_aim[:time] - (time + bullet_duration) < 1
        fire 3
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
