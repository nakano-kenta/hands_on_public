class Battlefield
  include Coordinate

  attr_reader :width
  attr_reader :height
  attr_reader :robots
  attr_reader :teams
  attr_reader :bullets
  attr_reader :explosions
  attr_reader :time
  attr_reader :seed
  attr_reader :timeout  # how many ticks the match can go before ending.
  attr_reader :game_over

  def initialize width, height, timeout, round, slow
    @width, @height = width, height
    @round = round
    @time = 0
    @robots = []
    @teams = Hash.new{|h,k| h[k] = [] }
    @bullets = []
    @explosions = []
    @timeout = timeout
    @slow = slow
    @game_over = false
  end

  def << object
    case object
    when RobotRunner
      @robots << object
      @teams[object.team] << object
      object.team_members = @teams[object.team]
    when Bullet
      @bullets << object
    when Explosion
      @explosions << object
    end
  end

  def before_start
    puts "==== Round #{@round} start ==="
    @teams.each do |team_name, robots|
      puts "#{team_name}: #{robots.map(&:uniq_name).join ' '}"
    end

    robots.each do |robot|
      begin
        robot.send :before_start unless robot.dead
      rescue Exception => bang
        puts "#{robot} made an exception:"
        puts "#{bang.class}: #{bang}", bang.backtrace
        robot.instance_eval{@energy = -1}
      end
    end
  end

  def impact_to_damage(impact)
    (impact / 2) ** 2 / 2.5
  end

  ELASTIC_MODULUS = 0.6.freeze
  def tick
    before_start if @time == 0

    explosions.delete_if{|explosion| explosion.dead}
    explosions.each{|explosion| explosion.tick}

    bullets.delete_if{|bullet| bullet.dead}
    bullets.each{|bullet| bullet.tick}

    robots.each do |robot|
      begin
        robot.send :internal_tick unless robot.dead
      rescue Exception => bang
        raise if bang.instance_of? Interrupt
        puts "#{robot} made an exception:"
        puts "#{bang.class}: #{bang}", bang.backtrace
        robot.instance_eval{@energy = -1}
      end
    end

    robots.each_with_index do |r1, index|
      next if r1.dead
      robots[(index+1)..-1].each do |r2|
        next if r1 == r2
        next if r2.dead
        difference = Math.hypot(r1.x - r2.x, r1.y - r2.y)
        if difference <= 80
          r1_heading = to_direction({x: r1.prev_x, y: r1.prev_y}, {x: r1.x, y: r1.y})
          r2_heading = to_direction({x: r2.prev_x, y: r2.prev_y}, {x: r2.x, y: r2.y})
          r1_heading = r2.heading if r1.speed.abs <= 0.1
          r2_heading = r1.heading if r2.speed.abs <= 0.1
          crash_angle = angle_to_direction(r1_heading - r2_heading)
          crash_heading = to_direction({x: r1.x, y: r1.y}, {x: r2.x, y: r2.y})
          r1_delta_angle = (crash_heading - r1_heading).to_rad
          r2_delta_angle = (crash_heading - r2_heading + 180).to_rad
          impact = Math.cos(r1_delta_angle)*r1.speed.abs + Math.cos(r2_delta_angle)*r2.speed.abs
          damage = impact_to_damage impact

          crash_move_distance = (80 - difference) / 2
          crash_move_distance += impact * ELASTIC_MODULUS / 2

          r1_distance = to_distance({x: r1.prev_x, y: r1.prev_y}, {x: r1.x, y: r1.y})
          r2_distance = to_distance({x: r2.prev_x, y: r2.prev_y}, {x: r2.x, y: r2.y})

          r2_point = to_point(crash_heading, crash_move_distance, {x: r2.x, y: r2.y})
          r2.x = r2_point[:x]
          r2.y = r2_point[:y]
          r2.energy -= damage

          r1_point = to_point(crash_heading + 180, crash_move_distance, {x: r1.x, y: r1.y})
          r1.x = r1_point[:x]
          r1.y = r1_point[:y]
          r1.energy -= damage

          r1_distance = to_distance({x: r1.prev_x, y: r1.prev_y}, {x: r1.x, y: r1.y})
          r2_distance = to_distance({x: r2.prev_x, y: r2.prev_y}, {x: r2.x, y: r2.y})
          if r1.speed > 0
            r1.speed = r1_distance * Math.cos((r1_heading - to_direction({x: r1.prev_x, y: r1.prev_y}, {x: r1.x, y: r1.y})).to_rad)
          else
            r1.speed = -r1_distance * Math.cos((r1_heading - to_direction({x: r1.prev_x, y: r1.prev_y}, {x: r1.x, y: r1.y})).to_rad)
          end
          if r2.speed > 0
            r2.speed = r2_distance * Math.cos((r2_heading - to_direction({x: r2.prev_x, y: r2.prev_y}, {x: r2.x, y: r2.y})).to_rad)
          else
            r2.speed = -r2_distance * Math.cos((r2_heading - to_direction({x: r2.prev_x, y: r2.prev_y}, {x: r2.x, y: r2.y})).to_rad)
          end
          if r1.team == r2.team
            r1.friend_ram_damage_given += damage
            r2.friend_ram_damage_given += damage
            if r2.dead
              r1.friend_kills += 1
              r1.friend_ram_kills += 1
            end
            if r1.dead
              r2.friend_kills += 1
              r2.friend_ram_kills += 1
            end
          else
            r1.ram_damage_given += damage
            r2.ram_damage_given += damage
            if r2.dead
              r1.kills += 1
              r1.ram_kills += 1
            end
            if r1.dead
              r2.kills += 1
              r2.ram_kills += 1
            end
          end
          r1.ram_damage_taken += damage
          r2.ram_damage_taken += damage
          r1.events['crash_into_enemy'] << {
            with: r2.uniq_name,
            damage: damage
          }
          r2.events['crash_into_enemy'] << {
            with: r1.uniq_name,
            damage: damage
          }
        end
      end
      r1.after_move
    end

    robots.each do |robot|
      begin
        robot.send :after_tick unless robot.dead
      rescue Exception => bang
        raise if bang.instance_of? Interrupt
        puts "#{robot} made an exception:"
        puts "#{bang.class}: #{bang}", bang.backtrace
        robot.instance_eval{@energy = -1}
      end
    end

    @time += 1
    sleep @slow if @slow.to_f > 0
    live_robots = robots.find_all{|robot| !robot.dead}
    @game_over = (  (@time >= @timeout) or # timeout reached
                    (live_robots.length <= 1) or # no robots alive, draw game
                    (bullets.length == 0 and
                    (live_robots.all?{|r| r.team == live_robots.first.team}))) # all other teams are dead
    if @game_over
      robots.map(&:game_over)
    end
    not @game_over
  end

  def state
    {:explosions => explosions.map{|e| e.state},
     :bullets    => bullets.map{|b| b.state},
     :robots     => robots.map{|r| r.state}}
  end
end
