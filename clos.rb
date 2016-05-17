
module Clos

  class Object

  #   def method_missing(method, *args)
  #     if method.to_s['=']
  #       self.define_singleton_method(method) do |*_|
  #         self.instance_variable_set("@#{method[0..-2]}", args.first)
  #       end
  #     else
  #       self.define_singleton_method(method) do
  #         self.instance_variable_get("@#{method}")
  #       end
  #     end
  #     self.send(method, *args) rescue super
  #   end

  end

  class LookupStack

    def initialize(bindings = [])
      @bindings = bindings
    end

    def method_missing(m, *args)
      @bindings.reverse_each do |bind|
        begin
          method = eval("method(%s)" % m.inspect, bind)
        rescue NameError
        else
          return method.call(*args)
        end
        begin
          value = eval(m.to_s, bind)
          return value
        rescue NameError
        end
      end
      raise NoMethodError
    end

    def push_binding(bind)
      @bindings.push bind
    end

    def push_instance(obj)
      @bindings.push obj.instance_eval { binding }
    end

    def push_hash(vars)
      push_instance Struct.new(*vars.keys).new(*vars.values)
    end

    def run_proc(p, *args)
      instance_exec(*args, &p)
    end

    def run_proc_with_args(p, args) # input array, do not pack it
      instance_exec(*args, &p)
    end

  end

  class Proc < ::Proc           # proc for genericFunction

    def apply_with_next_method(next_method, args)
      stack = LookupStack.new
      stack.push_hash(:nextMethod => next_method)
      stack.run_proc_with_args(self, args)
    end

    def call_with_binding(bind, *args)
      LookupStack.new([bind]).run_proc(self, *args)
    end

  end

  ### for ClosObject
  # class_of -> obj.class
  # class_cpl -> obj.class.ancestors
  # is_a -> obj.is_a?
  # compute_simple_cpl -> ___

  ### for generic function
  # add_method -> generic.addmethod

  class GenericFunctor < Proc
    attr_accessor :generic

    def addMethod(*args, &impl)
      Clos.addMethod(@generic, *args, &impl)
    end

    def to_s
      "<GenericFunctor:#{@generic.to_s}>"
    end

  end

  class Generic

    attr_reader :name, :options, :functor

    # for test
    # attr_reader :methods, :before, :after, :around, :primary

    def initialize(name, options = {})
      # #TODO: options:
      # - the param count
      # - cache : default is true
      # - single_method : without combination
      @options = {cache:false}.merge! options
      @functor = nil
      @name = name
      @methods = []             # the methods in generic function
      # cache
      @cached_qualifier = false
      @before, @after, @around, @primary = [], [], [], []
    end

    def functor                 # compute_apply_generic
      return @functor if @functor
      @functor = GenericFunctor.new { |*arguments|
        run(sort_method_with(arguments), arguments)
      }
      @functor.generic = self
      @functor
    end

    # add method to this generic
    def addmethod(qualifier, specs, &impl)
      #TODO: clean the cache of :before, :after, :around, and :primary
      unless /^(before|around|after|primary)$/.match qualifier.to_s
        raise("Unknown method qualifier " + qualifier)
      end
      # #TODO: if (typeof generic == "function") generic = generic.O$_generic;
      # allocate method
      newm = Method.new(@name, qualifier, specs, &impl)
      @methods.select! { |m| !is_specializers_same?(m, newm) }
      @methods.push newm         # add to last
      return newm
    end

    # more friendly method
    def addMethod(*args, &impl)
      Clos.addMethod(self, *args, &impl)
    end

    # static
    # check if the specializers is the same
    def is_specializers_same?(m1, m2)
      s1, s2 = m1.specializers, m2.specializers
      unless s1.length == s2.length
        raise("Different number of specializers in two methods")
      end
      (m1.qualifier == m2.qualifier) and (s1 == s2)
    end

    # static
    # compare two class in ancestors
    def compare_class_with_arg(c1, c2, arg)
      return -1 if !c1.is_a?(Module)
      return 1 if !c2.is_a?(Module)
      cpl = arg.class.ancestors
      cpl.index(c1) - cpl.index(c2)
    end

    # static
    # compare two method with the input args
    def compare_method_with_args(m1, m2, args)
      s1, s2 = m1.specializers, m2.specializers
      unless s1.length == s2.length
        raise("Different number of specializers in two methods")
      end
      s1.length.times do |i|
        return compare_class_with_arg(s1[i], s2[i], args[i]) unless s1[i] == s2[i]
      end
      return -1 if m1.qualifier == :around
      return 1 if m2.qualifier == :around
      return 0 # no use
    end

    # static
    # check if a spec is applicable with arg
    def is_applicable?(spec, arg)
      return arg.is_a? spec if spec.is_a? Module
      return arg == spec        # default is value
    end

    # static
    def is_all_applicable?(specs, args)
      specs.length.times do |i|
        return false unless is_applicable?(specs[i], args[i])
      end
      return true
    end

    # compute_methods
    def sort_method_with(args) # packed args
      applicable_methods = @methods.select do |m|
        is_all_applicable?(m.specializers, args)
      end
      return applicable_methods.sort! do |m1, m2|
        compare_method_with_args(m1, m2, args)
      end
    end

    def one_step(methods, args)       # (methods, args -> (arguments -> result))
      # if arguments is nil, then use args
      proc do |*arguments|
        if methods.length == 0
          raise("No applicable (next) methods in: " + @name + "\n" + args.to_s + "\n" + arguments.to_s)
        end
        # for inner function optimize the last
        temp_args = arguments.length > 0 ? arguments : args
        if methods.length > 1
          methods[0].apply(one_step(methods.drop(1), args), temp_args)
        else
          methods[0].is_a?(Method) ?
            methods[0].apply_nil(temp_args) :
            methods[0].call(*temp_args)
        end
      end
    end

    def inner(args)
      @before.each { |m| m.apply_nil(args) } # method call
      result = one_step(@primary, args).call(*args) # my proc call
      @after.each { |m| m.apply_nil(args) }
      return result
    end

    # compute_apply_methods
    def run(methods, args) # input the sorted methods, and the args
      @before, @after, @around, @primary = [], [], [], [] #TODO: cache these list
      methods.each do |m|
        case m.qualifier
        when :before then @before.push m
        when :after then @after.push m
        when :around then @around.push m
        when :primary then @primary.push m
        else raise("Unknown qualifier " + m.qualifier.to_s)
        end
      end

      return inner(args) if @around.length == 0

      return one_step(
        @around + [proc { inner(args) }], args
      ).call(*args)

    end

    def to_s
      "<GenericFunction:#{@name}>"
    end

  end

  class Method

    def initialize(name, qualifier, specs, &impl)
      @name = name
      @qualifier = qualifier
      @specializers = specs
      @implementation = Proc.new(&impl)
    end

    def apply_nil(args)
      @implementation.call(*args)
    end

    def apply(next_method, args)
      @implementation.apply_with_next_method(next_method, args)
    end

    attr_reader :name, :qualifier, :specializers, :implementation

    def to_s
      "<GenericMethod:#{@name},#{@qualifier}"
    end

  end

  def self.defGeneric(name, option = {})
    Generic.new(name, option).functor
  end

  # add method to the generic
  am = Generic.new("addmethod")
  @@amf_M_generic = am.functor

  def self.addMethod(*args, &impl)
    @@amf_M_generic.(*args, impl)
  end

  am.addmethod :primary, [Symbol, Generic, Array, ::Proc] do
    |qualifier, generic, specs, impl|
    generic.addmethod qualifier, specs, &impl
  end

  am.addmethod :primary, [Generic, Symbol, Array, ::Proc] do
    |generic, qualifier, specs, impl|
    generic.addmethod qualifier, specs, &impl
  end

  am.addmethod :primary, [Generic, Array, ::Proc, nil] do
    |generic, specs, impl|
    generic.addmethod :primary, specs, &impl
  end

  # new function of ClosObject
  @@init_M_generic = Generic.new("initialize").functor
  @@init_M_generic.addMethod [BasicObject] {nil} # default is nil

  def self.init
    @@init_M_generic
  end

  def self.new(klass, *args, &b)
    result = klass.new(*args, &b)
    @@init_M_generic.(result)
    result
  end

  # #TODO: ClosObject
  def self.defclass
    :closClass
  end

end
