class Bullet
  attr_accessor :x
  attr_accessor :y
  attr_accessor :heading
  attr_accessor :speed
  attr_accessor :energy
  attr_accessor :dead
  attr_accessor :origin

  def initialize bf, x, y, heading, speed, energy, origin
    @x, @y, @heading, @origin = x, y, heading, origin
    @speed, @energy = speed, energy
    @battlefield, @dead = bf, false
  end

  def state
    {:x=>x, :y=>y, :energy=>energy}
  end

  def tick
    return if @dead
    @x += Math::cos(@heading.to_rad) * @speed
    @y -= Math::sin(@heading.to_rad) * @speed

    @dead ||= (@x < 0) || (@x >= @battlefield.width)
    @dead ||= (@y < 0) || (@y >= @battlefield.height)

    @battlefield.robots.each do |other|
      if (other != origin) && (Math.hypot(@y - other.y, other.x - @x) < 40) && (!other.dead)
        explosion = Explosion.new(@battlefield, other.x, other.y, @energy)
        @battlefield << explosion
        damage = other.hit(self)
        if origin.team == other.team
          origin.friend_damage_given += damage
          origin.friend_bullet_damage_given += damage
          origin.friend_kills += 1 if other.dead
        else
          origin.damage_given += damage
          origin.bullet_damage_given += damage
          origin.kills += 1 if other.dead
        end
        other.damage_taken += damage
        other.bullet_damage_taken += damage
        @dead = true
      end
    end
  end
end
