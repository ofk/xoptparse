# frozen_string_literal: true

require 'test_helper'

class XOptionParserTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute { ::XOptionParser::VERSION.nil? }
  end

  def test_simple_parse
    create_option_parser = proc do |res = {}|
      [XOptionParser.new do |o|
        o.on('-o') { res[:o] = true }
      end, res]
    end

    opt, res = create_option_parser.call
    argv = opt.parse!([])
    assert { argv.empty? }
    assert { res == {} }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[-o])
    assert { argv.empty? }
    assert { res == { o: true } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[-o v])
    assert { argv == %w[v] }
    assert { res == { o: true } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[v -o])
    assert { argv == %w[v] }
    assert { res == { o: true } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[v])
    assert { argv == %w[v] }
    assert { res == {} }
  end

  def test_info
    params = {}
    opt = XOptionParser.new do |o|
      o.on('--foo-bar VAL', &:itself)
      o.on('--baz_qux VAL', &:itself)
      o.on('hoge-fuga', &:itself)
      o.on('[piyo_hogera]', &:itself)
      o.on('foo...', &:itself)
      o.on('bar baz') { |*vals| vals }
    end
    opt.parse!(%w[--foo-bar 1 --baz_qux 2 hoge-fuga piyo_hogera foo bar baz], into: params)
    assert { params == { 'foo-bar': '1', baz_qux: '2', 'hoge-fuga': 'hoge-fuga', piyo_hogera: 'piyo_hogera', foo: ['foo'], bar: %w[bar baz] } }

    params = {}
    opt = XOptionParser.new do |o|
      o.on('val', &:itself)
      o.command('foo') do |o2|
        o2.on('--bar', &:itself)
        o2.on('hoge', &:itself)
      end
      o.command('baz') do |o2|
        o2.on('--qux', &:itself)
        o2.on('fuga', &:itself)
      end
    end
    opt.parse!(%w[str foo --bar baz], into: params)
    assert { params == { val: 'str', foo: { bar: true, hoge: 'baz' } } }
  end

  def test_flag
    create_option_parser = proc do
      XOptionParser.new do |o|
        o.on('--[no-]flag [FLAG]', &:itself)
        o.on('--[no-]good [FLAG]', TrueClass, &:itself)
        o.on('--[no-]bad [FLAG]', FalseClass, &:itself)
        o.on('-x', '--[no-]flag_two [FLAG]', &:itself)
        o.on('-y', '--[no-]good_two [FLAG]', TrueClass, &:itself)
        o.on('-z', '--[no-]bad_two [FLAG]', FalseClass, &:itself)
      end
    end

    params = {}
    args = create_option_parser.call.parse!([], into: params)
    assert { args.empty? }
    assert { params == {} }

    params = {}
    args = create_option_parser.call.parse!(%w[--flag --good --bad --flag-two --good-two --bad-two], into: params)
    assert { args.empty? }
    assert { params == { flag: true, good: true, bad: false, flag_two: true, good_two: true, bad_two: false } }

    params = {}
    args = create_option_parser.call.parse!(%w[--flag yes --good yes --bad yes --flag-two yes --good-two yes --bad-two yes], into: params)
    assert { args.empty? }
    assert { params == { flag: 'yes', good: true, bad: true, flag_two: 'yes', good_two: true, bad_two: true } }

    params = {}
    args = create_option_parser.call.parse!(%w[--flag no --good no --bad no --flag-two no --good-two no --bad-two no], into: params)
    assert { args.empty? }
    assert { params == { flag: 'no', good: false, bad: false, flag_two: 'no', good_two: false, bad_two: false } }

    params = {}
    args = create_option_parser.call.parse!(%w[--no-flag --no-good --no-bad --no-flag-two --no-good-two --no-bad-two], into: params)
    assert { args.empty? }
    assert { params == { flag: false, good: false, bad: false, flag_two: false, good_two: false, bad_two: false } }

    params = {}
    args = create_option_parser.call.parse!(%w[-x -y -z], into: params)
    assert { args.empty? }
    assert { params == { flag_two: true, good_two: true, bad_two: false } }

    params = {}
    args = create_option_parser.call.parse!(%w[-x yes -y yes -z yes], into: params)
    assert { args.empty? }
    assert { params == { flag_two: 'yes', good_two: true, bad_two: true } }

    params = {}
    args = create_option_parser.call.parse!(%w[-x no -y no -z no], into: params)
    assert { args.empty? }
    assert { params == { flag_two: 'no', good_two: false, bad_two: false } }
  end

  def test_sub_command
    create_option_parser = proc do |res = {}|
      [XOptionParser.new do |o|
        res[:c] = :root
        res[:o] = nil
        o.on('-o') { res[:o] = :root }
        o.command('foo') do |o2|
          res[:c] = :foo
          o2.on('-o') { res[:o] = :foo }
          o2.command('hoge_hoge') do |o3|
            res[:c] = :hoge
            o3.on('-o') { res[:o] = :hoge }
          end
        end
        o.command('bar') do
          res[:c] = :bar
        end
      end, res]
    end

    opt, res = create_option_parser.call
    argv = opt.parse!([])
    assert { argv.empty? }
    assert { res == { c: :root, o: nil } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[-o])
    assert { argv.empty? }
    assert { res == { c: :root, o: :root } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[-o foo])
    assert { argv.empty? }
    assert { res == { c: :foo, o: :root } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[foo])
    assert { argv.empty? }
    assert { res == { c: :foo, o: nil } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[foo -o])
    assert { argv.empty? }
    assert { res == { c: :foo, o: :foo } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[foo -o hoge_hoge])
    assert { argv.empty? }
    assert { res == { c: :hoge, o: :foo } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[foo hoge-hoge -o])
    assert { argv.empty? }
    assert { res == { c: :hoge, o: :hoge } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[foo hogeHoge fuga])
    assert { argv == %w[fuga] }
    assert { res == { c: :hoge, o: nil } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[bar])
    assert { argv.empty? }
    assert { res == { c: :bar, o: nil } }

    opt = create_option_parser.call.first
    assert_raises(OptionParser::InvalidOption) { opt.parse!(%w[--bar]) }
  end

  def test_arguments
    create_option_parser = proc do |res = {}|
      [XOptionParser.new do |o|
        o.on('v1') { |v| res[:v1] = v }
        o.on('[v2] v3') do |v2, v3|
          res[:v2] = v2
          res[:v3] = v3
        end
      end, res]
    end

    opt = create_option_parser.call.first
    assert_raises(XOptionParser::MissingArgument) { opt.parse!([]) }

    opt = create_option_parser.call.first
    assert_raises(XOptionParser::MissingArgument) { opt.parse!(%w[a]) }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[a b])
    assert { argv.empty? }
    assert { res == { v1: 'a', v2: nil, v3: 'b' } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[a b c])
    assert { argv.empty? }
    assert { res == { v1: 'a', v2: 'b', v3: 'c' } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[a b c d])
    assert { argv == %w[d] }
    assert { res == { v1: 'a', v2: 'b', v3: 'c' } }
  end

  def test_rest_arguments
    create_option_parser = proc do |res = {}|
      [XOptionParser.new do |o|
        o.on('v1 [v2]') do |v1, v2|
          res[:v1] = v1
          res[:v2] = v2
        end
        o.on('v3...') { |v3| res[:v3] = v3 }
        o.on('v4') { |v4| res[:v4] = v4 }
      end, res]
    end

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[a b c])
    assert { argv.empty? }
    assert { res == { v1: 'a', v2: nil, v3: %w[b], v4: 'c' } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[a b c d e f])
    assert { argv.empty? }
    assert { res == { v1: 'a', v2: 'b', v3: %w[c d e], v4: 'f' } }
  end

  def test_arguments_as_option
    create_option_parser = proc do |res = {}|
      [XOptionParser.new do |o|
        o.on('v1') { |v| res[:v1] = v }
        o.on('[v2]') { |v| res[:v2] = v }
        o.on('v3') { |v| res[:v3] = v }
      end, res]
    end

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[--v3 a b])
    assert { argv.empty? }
    assert { res == { v1: 'b', v3: 'a' } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[--v3 a --v1 b c])
    assert { argv.empty? }
    assert { res == { v1: 'b', v2: 'c', v3: 'a' } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[--v3 a --v2 b c])
    assert { argv.empty? }
    assert { res == { v1: 'c', v2: 'b', v3: 'a' } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[--v3 a --v1 b --v2 c])
    assert { argv.empty? }
    assert { res == { v1: 'b', v2: 'c', v3: 'a' } }
  end

  def test_rest_arguments_as_option
    create_option_parser = proc do |res = {}|
      [XOptionParser.new do |o|
        o.on('v1') { |v| res[:v1] = v }
        o.on('[v2]') { |v| res[:v2] = v }
        o.on('v3...') { |v| res[:v3] = v }
        o.on('v4') { |v| res[:v4] = v }
      end, res]
    end

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[--v4 a --v3 b c])
    assert { argv.empty? }
    assert { res == { v1: 'c', v3: %w[b], v4: 'a' } }

    opt, res = create_option_parser.call
    argv = opt.parse!(%w[--v4 a --v1 b --v2 c d e f])
    assert { argv.empty? }
    assert { res == { v1: 'b', v2: 'c', v3: %w[d e f], v4: 'a' } }
  end

  def test_arguments_with_type
    res = {}
    opt = XOptionParser.new do |o|
      o.on('port', Numeric) { |v| res[:port] = v }
      o.on('bools...', TrueClass) { |v| res[:bools] = v }
      o.on('values', Array) { |v| res[:values] = v }
    end
    opt.parse!(%w[80 yes no + - a,b,c])
    assert { res == { port: 80, bools: [true, false, true, false], values: %w[a b c] } }
  end

  def test_arguments_and_sub_command
    create_option_parser = proc do |res = {}|
      [XOptionParser.new do |o|
        res[:c] = :root
        o.command('foo') do |o2|
          res[:c] = :foo
          o2.on('[v1]') { |v| res[:v1] = v }
        end
        o.on('v2') { |v| res[:v2] = v }
        o.on('[v3]') { |v| res[:v3] = v }
        o.command('bar') do |o2|
          res[:c] = :bar
          o2.on('[v4]') { |v| res[:v4] = v }
        end
      end, res]
    end

    opt = create_option_parser.call.first
    opt.program_name = 'test'
    assert { opt.help == "Usage: test v2 [v3] <command>\n    foo\n    v2\n    [v3]\n    bar\n" }

    opt, res = create_option_parser.call
    args = opt.parse!(%w[hoge piyo])
    assert { args.empty? }
    assert { res == { c: :root, v2: 'hoge', v3: 'piyo' } }

    opt, res = create_option_parser.call
    args = opt.parse!(%w[hoge])
    assert { args.empty? }
    assert { res == { c: :root, v2: 'hoge' } }

    opt, res = create_option_parser.call
    args = opt.parse!(%w[hoge bar])
    assert { args.empty? }
    assert { res == { c: :bar, v2: 'hoge' } }

    opt, res = create_option_parser.call
    args = opt.parse!(%w[hoge bar baz])
    assert { args.empty? }
    assert { res == { c: :bar, v2: 'hoge', v4: 'baz' } }

    opt, res = create_option_parser.call
    args = opt.parse!(%w[hoge bar baz qux])
    assert { args == %w[qux] }
    assert { res == { c: :bar, v2: 'hoge', v4: 'baz' } }

    opt, res = create_option_parser.call
    args = opt.parse!(%w[foo])
    assert { args.empty? }
    assert { res == { c: :foo } }

    opt, res = create_option_parser.call
    args = opt.parse!(%w[foo bar])
    assert { args.empty? }
    assert { res == { c: :foo, v1: 'bar' } }

    opt, res = create_option_parser.call
    args = opt.parse!(%w[foo bar baz])
    assert { args == %w[baz] }
    assert { res == { c: :foo, v1: 'bar' } }
  end

  def test_help
    opt = XOptionParser.new
    opt.program_name = 'test'
    assert { opt.help == "Usage: test\n" }

    opt.separator ''
    opt.separator 'Options:'
    opt.on('-t', '--test[=VAL]', 'test desc')
    assert { opt.help == "Usage: test [options]\n\nOptions:\n    -t, --test[=VAL]                 test desc\n" }

    opt.on('VALUE', 'value desc')
    assert { opt.help == "Usage: test [options] VALUE\n\nOptions:\n    -t, --test[=VAL]                 test desc\n    VALUE                            value desc\n" }

    opt.separator ''
    opt.separator 'Commands:'
    opt.command('sub', 'sub desc') do |o|
      o.separator ''
      o.separator 'Options:'
      o.on('-u', '--uest[=VAL]', 'uest desc')
    end
    opt.command('other')
    assert { opt.help == "Usage: test [options] VALUE <command>\n\nOptions:\n    -t, --test[=VAL]                 test desc\n    VALUE                            value desc\n\nCommands:\n    sub                              sub desc\n    other\n" }

    opt = opt.instance_variable_get(:@commands)['sub'].block.call
    assert { opt.help == "Usage: test sub [options]\n\nsub desc\n\nOptions:\n    -u, --uest[=VAL]                 uest desc\n" }
  end
end
