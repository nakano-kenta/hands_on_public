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
        puts "#{robot} made an exception:"
        puts "#{bang.class}: #{bang}", bang.backtrace
        robot.instance_eval{@energy = -1}
      end
    end

    robots.each_with_index do |r1, index|
      robots[(index+1)..-1].each do |r2|
        next if r1 == r2
        difference = Math.hypot(r1.x - r2.x, r1.y - r2.y)
        if difference <= 80
          r1_heading = to_direction({x: r1.prev_x, y: r1.prev_y}, {x: r1.x, y: r1.y})
          r2_heading = to_direction({x: r2.prev_x, y: r2.prev_y}, {x: r2.x, y: r2.y})
          crash_angle = angle_to_direction(r1_heading - r2_heading)

          r1_crash_heading = (angle_to_direction(crash_angle - r1_heading).abs < 90) ? (r1_heading + 180) : r1_heading
          r1_crash_distance = to_distance(to_point(r1_crash_heading, difference, {x: r1.x, y: r1.y}), {x: r2.x, y: r2.y})
          r2_crash_heading = (angle_to_direction(crash_angle - r2_heading).abs < 90) ? r2_heading : (r2_heading + 180)
          r2_crash_distance = to_distance(to_point(r2_crash_heading, difference, {x: r2.x, y: r2.y}), {x: r1.x, y: r1.y})
          p1 = to_point(r1_crash_heading, difference, {x: r1.x, y: r1.y})
          p2 = to_point(r2_crash_heading, difference, {x: r2.x, y: r2.y})
          Gosu.draw_rect(p1[:x]/2-5,p1[:y]/2-5,10,10,Gosu::Color.argb(0xff_ffffff), 2)
          Gosu.draw_rect(p2[:x]/2-5,p2[:y]/2-5,10,10,Gosu::Color.argb(0xff_ffffff), 2)

          p "CRASH(#{difference}) #{crash_angle}: #{r1.uniq_name} #{r1_heading} (#{r1.speed}): #{r1_crash_distance} =>  #{r2.uniq_name} #{r2_heading} (#{r2.speed}): #{r2_crash_distance}"

          if crash_angle.abs < 90
            if r1_crash_distance <= 60
              p "#{r1.uniq_name}: follow deep"
            else
              p "#{r1.uniq_name}: follow touch"
            end
            if r2_crash_distance <= 60
              p "#{r2.uniq_name}: follow deep"
            else
              p "#{r2.uniq_name}: follow touch"
            end
          else
            if r1_crash_distance <= 60
              p "#{r1.uniq_name}: against deep"
              r1.speed = 0
            else
              p "#{r1.uniq_name}: against touch"
            end
            if r2_crash_distance <= 60
              p "#{r2.uniq_name}: against deep"
              r2.speed = 0
            else
              p "#{r2.uniq_name}: against touch"
            end
          end
          crash_heading = to_direction({x: r1.x, y: r1.y}, {x: r2.x, y: r2.y})
          crash_move_distance = (80 - difference)
          r2_point = to_point(crash_heading, crash_move_distance, {x: r2.x, y: r2.y})
          r2.x = r2_point[:x]
          r2.y = r2_point[:y]
          r1_point = to_point(-crash_heading, crash_move_distance, {x: r1.x, y: r1.y})
          r1.x = r1_point[:x]
          r1.y = r1_point[:y]

          sleep 5
        end
      end
    end

    robots.each do |robot|
      begin
        robot.send :after_tick unless robot.dead
      rescue Exception => bang
        puts "#{robot} made an exception:"
        puts "#{bang.class}: #{bang}", bang.backtrace
        robot.instance_eval{@energy = -1}
      end
    end

    @time += 1
    sleep @slow if @slow.to_f > 0
    live_robots = robots.find_all{|robot| !robot.dead}
    @game_over = (  (@time >= @timeout) or # timeout reached
                    (live_robots.length == 0) or # no robots alive, draw game
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
