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

  def test_Generic_nextMethod
    t = Clos::Generic.new "test"
    tf = t.functor
    t.addmethod(:primary, [Object, Object]) { |o1, o2| "default"}
    t.addmethod(:primary, [Integer, Integer]) { |i1, i2|
      nextMethod.call + "0"
    }
    assert_equal tf[1,1], "default0"
  end

  def test_Generic_defaultParam
    t = Clos::Generic.new "test"
    tf = t.functor
    t.addmethod :primary, [Object, Object] { |o1, o2| "default"}
    # pass one param, the rest is nil
    assert_equal tf[1], "default"
    # rewrite and reduce a param in block
    t.addmethod :primary, [Object, Object] { |o1, o2| "default1"}
    # use Clos.addmethod
    Clos.addMethod(:primary, t, [Object, Object]) { |o1| "default1"}
    Clos.addMethod(t, [Object, Object]) { |o1| "default1"}
    assert_equal tf[1], "default1"
    # use friendly addMethod
    t.addMethod([Object, Object]) { "default1" }
    assert_equal tf[1], "default1"
  end

  def test_Generic_ValueDefine
    t = Clos.defGeneric "t"
    t.addMethod [Object, Object] {:default}
    t.addMethod [Integer, 1] {:value}
    t.addMethod [Integer, Integer] {:integer}
    assert_equal t[1,1], :value
    assert_equal t[1,3], :integer
  end

  def test_Generic_around
    g = Clos.defGeneric "generic" # use more friendly method
    g.addMethod [Integer] { "primary"}
    g.addMethod :around, [Integer] {
      "around+" + nextMethod.call
    }
    assert_equal g[1], "around+primary"
    g.addMethod :around, [Integer] { # overwrite the last one
      "around1+" + nextMethod.call
    }
    assert_equal g[1], "around1+primary"
  end

  def test_Generic_before_after
    g = Clos.defGeneric "generic"
    a = []
    g.addMethod [Integer] { |i| a << 1}
    g.addMethod :before, [Integer] {a << 0}
    g.addMethod :after, [Integer] {a << 2}
    assert_equal [0,1,2], g[1]
    a = []
    g.addMethod :after, [Integer] {a << 3}
    assert_equal [0,1,3], g[1]
  end

  # test with class type
  module Ma
    attr_accessor :a
  end

  module Mb
    attr_accessor :b
  end

  class A
    include Ma
    include Mb
    attr_accessor :v
  end

  def test_Object_dispatch
    g = Clos.defGeneric "generic"
    g.addMethod [A] { |a| a.v = :A_Value }
    g.addMethod :before, [Ma] { |ma| ma.a = 1 }
    g.addMethod :before, [Mb] { |mb| mb.b = 233 }
    result = A.new
    g.(result)
    assert_equal 1, result.a
    assert_equal 233, result.b
    assert_equal :A_Value, result.v
  end

  def test_Object_friendlyDefinition
    Clos.init.addMethod [A] { |a|
      a.v = :v
      nextMethod.call           # (call-next-method)
    }
    Clos.init.addMethod :before, [Ma] { |m| m.a = 1 }
    Clos.init.addMethod [Mb] { |m| m.b = 1 }

    result = Clos.new A
    assert_equal :v, result.v
    assert_equal 1, result.a
    assert_equal 1, result.b
  end

end
