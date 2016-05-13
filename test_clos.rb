require 'test/unit'
require './clos.rb'

class TestClos < Test::Unit::TestCase

  def test_Generic_create
    g = Clos::Generic.new "testg", {:config => 1}
    assert_equal(g.name, "testg")
  end

  def test_Generic_call
    t = Clos::Generic.new "test"
    t.addmethod(:primary, [Integer]) { |i| "result" + i.to_s }
    tf = t.functor
    assert_equal tf.call(1), "result1"
  end

  def test_Generic_Multiple
    t = Clos::Generic.new "test"
    tf = t.functor
    t.addmethod(:primary, [Integer, String]) { |i, s| i.to_s + s }
    t.addmethod(:primary, [Integer, Integer]) { |i1, i2| i1 + i2 }
    t.addmethod(:primary, [Object, Object]) { |o1, o2| "default" }
    assert_equal tf[1, "a"], "1a"
    assert_equal tf[1, 1], 2
    assert_equal tf[1, [1,2,3]], "default"
  end

end
