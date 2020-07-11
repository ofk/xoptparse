# frozen_string_literal: true

require 'test_helper'

class XOptionParserTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute { ::XOptionParser::VERSION.nil? }
  end

  def test_parse
    create_option_parser = proc do |res|
      XOptionParser.new do |o|
        o.on('-o') { res[:o] = true }
      end
    end

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!([])
    assert { argv.empty? }
    assert { res == {} }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[-o])
    assert { argv.empty? }
    assert { res == { o: true } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[-o v])
    assert { argv == %w[v] }
    assert { res == { o: true } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[v -o])
    assert { argv == %w[v] }
    assert { res == { o: true } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[v])
    assert { argv == %w[v] }
    assert { res == {} }
  end

  def test_sub_command
    create_option_parser = proc do |res|
      XOptionParser.new do |o|
        res[:c] = :root
        res[:o] = nil
        o.on('-o') { res[:o] = :root }
        o.command('foo') do |o2|
          res[:c] = :foo
          o2.on('-o') { res[:o] = :foo }
          o2.command('hoge') do |o3|
            res[:c] = :hoge
            o3.on('-o') { res[:o] = :hoge }
          end
        end
        o.command('bar') do
          res[:c] = :bar
        end
      end
    end

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!([])
    assert { argv.empty? }
    assert { res == { c: :root, o: nil } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[-o])
    assert { argv.empty? }
    assert { res == { c: :root, o: :root } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[-o foo])
    assert { argv.empty? }
    assert { res == { c: :foo, o: :root } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[foo])
    assert { argv.empty? }
    assert { res == { c: :foo, o: nil } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[foo -o])
    assert { argv.empty? }
    assert { res == { c: :foo, o: :foo } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[foo -o hoge])
    assert { argv.empty? }
    assert { res == { c: :hoge, o: :foo } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[foo hoge -o])
    assert { argv.empty? }
    assert { res == { c: :hoge, o: :hoge } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[foo hoge fuga])
    assert { argv == %w[fuga] }
    assert { res == { c: :hoge, o: nil } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[bar])
    assert { argv.empty? }
    assert { res == { c: :bar, o: nil } }
  end

  def test_arg_switch_ranges_validate
    # req
    assert { XOptionParser.valid_arg_switch_ranges?([1..1]) }
    assert { XOptionParser.valid_arg_switch_ranges?([1..1, 1..1, 1..1]) }
    # opt
    assert { XOptionParser.valid_arg_switch_ranges?([0..1]) }
    assert { XOptionParser.valid_arg_switch_ranges?([0..1, 0..1, 0..1]) }
    # req + opt
    assert { XOptionParser.valid_arg_switch_ranges?([1..1, 0..1]) }
    assert { XOptionParser.valid_arg_switch_ranges?([0..1, 1..1]) }
    assert { XOptionParser.valid_arg_switch_ranges?([1..1, 0..1, 1..1]) }
    # rest
    assert { XOptionParser.valid_arg_switch_ranges?([1..nil]) }
    assert { XOptionParser.valid_arg_switch_ranges?([0..nil]) }
    refute { XOptionParser.valid_arg_switch_ranges?([1..nil, 0..nil]) }
    # opt + rest
    assert { XOptionParser.valid_arg_switch_ranges?([0..1, 1..nil]) }
    refute { XOptionParser.valid_arg_switch_ranges?([1..nil, 0..1]) }
    # req + rest
    assert { XOptionParser.valid_arg_switch_ranges?([1..1, 1..nil]) }
    assert { XOptionParser.valid_arg_switch_ranges?([1..nil, 1..1]) }
    # req + opt + rest
    assert { XOptionParser.valid_arg_switch_ranges?([1..1, 0..1, 1..nil, 1..1]) }
  end

  def test_arguments
    create_option_parser = proc do |res|
      XOptionParser.new do |o|
        o.on('v1') { |v| res[:v1] = v }
        o.on('[v2] v3') do |v2, v3|
          res[:v2] = v2
          res[:v3] = v3
        end
      end
    end

    create_rest_option_parser = proc do |res|
      XOptionParser.new do |o|
        o.on('v1 [v2]') do |v1, v2|
          res[:v1] = v1
          res[:v2] = v2
        end
        o.on('v3...') { |v3| res[:v3] = v3 }
        o.on('v4') { |v4| res[:v4] = v4 }
      end
    end

    opt = create_option_parser.call({})
    assert_raises(XOptionParser::MissingArgument) { opt.parse!([]) }

    opt = create_option_parser.call({})
    assert_raises(XOptionParser::MissingArgument) { opt.parse!(%w[a]) }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[a b])
    assert { argv.empty? }
    assert { res == { v1: 'a', v2: nil, v3: 'b' } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[a b c])
    assert { argv.empty? }
    assert { res == { v1: 'a', v2: 'b', v3: 'c' } }

    res = {}
    opt = create_option_parser.call(res)
    argv = opt.parse!(%w[a b c d])
    assert { argv == %w[d] }
    assert { res == { v1: 'a', v2: 'b', v3: 'c' } }

    res = {}
    opt = create_rest_option_parser.call(res)
    argv = opt.parse!(%w[a b c])
    assert { argv.empty? }
    assert { res == { v1: 'a', v2: nil, v3: %w[b], v4: 'c' } }

    res = {}
    opt = create_rest_option_parser.call(res)
    argv = opt.parse!(%w[a b c d e f])
    assert { argv.empty? }
    assert { res == { v1: 'a', v2: 'b', v3: %w[c d e], v4: 'f' } }
  end

  def test_typed_arguments
    res = {}
    opt = XOptionParser.new do |o|
      o.on('port', Numeric) { |v| res[:port] = v }
      o.on('bools...', TrueClass) { |v| res[:bools] = v }
      o.on('values', Array) { |v| res[:values] = v }
    end
    opt.parse!(%w[80 yes no + - a,b,c])
    assert { res == { port: 80, bools: [true, false, true, false], values: %w[a b c] } }
  end
end
