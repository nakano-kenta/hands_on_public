class Explosion
  attr_accessor :x
  attr_accessor :y
  attr_accessor :t
  attr_accessor :dead
  attr_accessor :energy

  def initialize bf, x, y, e
    @x, @y, @t, @energy = x, y, 0, e
    @battlefield, @dead = bf, false
  end

  def state
    {:x=>x, :y=>y, :t=>t}
  end

  def tick
    @t += 1
    @dead ||= t > 15
  end
end
