defmodule Worker do
  @moduledoc """
  evlis for paralell uses this module
  """
  def eval do
    receive do
      {sender, {c, x, env, tr, prop}} -> send(sender, {:answer, [c, eval1(x, env, tr, prop)]})
    end
  end

  def eval1(x, env, tr, prop) do
    {s, _, _, _} = Eval.eval(x, env, :seq, tr, prop)
    s
  end
end

# ----------------eval-------------
defmodule Eval do
  use Bitwise

  @moduledoc """
  Evaluate S expression
  Return value is tuple. {val,env,tr,prop}
  eval(exp,env,mode,tr,prop)
  ## example
  iex>Eval.eval(:t,[],:para,[],[])
  {:t,[],[],[]}
  iex>Eval.eval(nil,[],:para,[],[])
  {nil,[],[],[]}
  iex>Eval.eval(1,[],:para,[],[])
  {1,[],[],[]}
  iex>Eval.eval(:a,[[:a|1]],:para,[],[])
  {1,[[:a|1]],[],[]}
  """
  def eval(:t, env, _, tr, prop) do
    {:t, env, tr, prop}
  end

  def eval(:T, env, _, tr, prop) do
    {:t, env, tr, prop}
  end

  def eval(nil, env, _, tr, prop) do
    {nil, env, tr, prop}
  end

  def eval(:NIL, env, _, tr, prop) do
    {nil, env, tr, prop}
  end

  def eval([], env, _, tr, prop) do
    {[], env, tr, prop}
  end

  def eval(x, env, _, tr, prop) when is_atom(x) do
    cond do
      is_upper_atom(x) ->
        {x, env, tr, prop}

      Enum.member?([:+, :-, :*, :/], x) ->
        {x, env, tr, prop}

      true ->
        s = assoc(x, env)
        {s, env, tr, prop}
    end
  end
  # number
  def eval(x, env, _, tr, prop) when is_number(x) do
    {x, env, tr, prop}
  end
  # string
  def eval(x, env, _, tr, prop) when is_binary(x) do
    {x, env, tr, prop}
  end
  # quote
  def eval([:quote, x], env, _, tr, prop) do
    {x, env, tr, prop}
  end
  # define
  def eval([:define, left, right], env, _, tr, prop) do
    [name | arg] = left
    env1 = [[name | {:func, arg, right}] | env]
    {name, env1, tr, prop}
  end
  # defun
  def eval([:defun, name, arg, body], env, _, tr, prop) do
    env1 = [[name | {:func, arg, body}] | env]
    {name, env1, tr, prop}
  end
  # setq
  def eval([:setq, name, arg], env, mode, tr, prop) do
    {s, _, _, _} = eval(arg, env, mode, tr, mode)
    env1 = [[name | s] | env]
    {s, env1, tr, prop}
  end
  # if
  def eval([:if, x, y, z], env, mode, tr, prop) do
    {x1, _, _, _} = eval(x, env, mode, tr, prop)

    if x1 != nil do
      eval(y, env, mode, tr, prop)
    else
      eval(z, env, mode, tr, prop)
    end
  end
  # cond
  def eval([:cond | arg], env, mode, tr, prop) do
    evcond(arg, env, mode, tr, prop)
  end
  # prog
  def eval([:prog, arg | body], env, mode, tr, prop) do
    env1 = pairlis(arg, make_nil(arg), env)
    evprog(body, env1, mode, tr, prop)
  end
  # lambda
  def eval([:lambda, args, body], env, _, tr, prop) do
    {{:func, args, body}, env, tr, prop}
  end
  # function
  def eval([:function, [:lambda, args, body]], env, _, tr, prop) do
    {{:funarg, args, body, env}, env, tr, prop}
  end
  # load
  def eval([:load, x], env, mode, tr, prop) do
    {x1, _, _, _} = eval(x, env, mode, tr, prop)
    ext = String.split(x1, ".") |> Enum.at(1)
    {status, string} = File.read(x1)

    if status == :error do
      throw("Error load")
    end

    cond do
      ext == "meta" or ext == nil ->
        env1 = load(env, Read.tokenize(string))
        {:t, env1, tr, prop}

      ext == "lsp" ->
        env1 = sload(env, Read.stokenize(string))
        {:t, env1, tr, prop}

      ext == "o" ->
        Code.compiler_options(ignore_module_conflict: true)
        Code.compile_string(string)
        {:t, env, tr, prop}
    end
  end
  # time
  def eval([:time, x], env, mode, tr, prop) do
    {time, {result, _, _, _}} = :timer.tc(fn -> eval(x, env, mode, tr, prop) end)
    IO.inspect("time: #{time} micro second")
    IO.inspect("-------------")
    {result, env, tr, prop}
  end
  # trace
  def eval([:trace, x], env, _, tr, prop) do
    {:t, env, [x | tr], prop}
  end
  # untrace
  def eval([:untrace, x], env, _, tr, prop) do
    tr1 = Keyword.delete(tr, x)
    {:t, env, tr1, prop}
  end

  def eval([:untrace], env, _, _, prop) do
    {:t, env, [], prop}
  end
  # function call
  def eval(x, env, mode, tr, prop) when is_list(x) do
    [f | args] = x

    cond do
      mode == :para ->
        funcall(f, paraevlis(args, env, tr, prop), env, mode, tr, prop)
      mode == :seq ->
        funcall(f, evlis(args, env, tr, prop), env, mode, tr, prop)
    end
  end

  # -----------apply--------------------------
  defp funcall(f, args, env, mode, tr, prop) when is_atom(f) do
    if is_subr(f) or Elxfunc.is_compiled(f) do
      primitive([f | args], env, mode, tr, prop)
    else
      if Enum.member?(tr, f) do
        Print.print([f | args])
      end

      expr = assoc(f, env)

      if expr == nil do
        Elxlisp.error("Not exist function error", f)
      end

      {:func, args1, body} = assoc(f, env)
      env1 = pairlis(args1, args, env)
      {s, _, _, _} = eval(body, env1, mode, tr, prop)
      {s, env, tr, prop}
    end
  end

  defp funcall({:func, args1, body}, args, env, mode, tr, prop) do
    env1 = pairlis(args1, args, env)
    {s, _, _, _} = eval(body, env1, mode, tr, prop)
    {s, env, tr, prop}
  end

  defp funcall({:funarg, args1, body, env2}, args, env, mode, tr, prop) do
    env1 = pairlis(args1, args, env)
    {s, _, _, _} = eval(body, env1 ++ env2, mode, tr, prop)
    {s, env, tr, prop}
  end

  defp evcond([], _, _, _, _) do
    nil
  end

  defp evcond([[p, e] | rest], env, mode, tr, prop) do
    {s, _, _, _} = eval(p, env, mode, tr, prop)

    if s != nil do
      eval(e, env, mode, tr, prop)
    else
      evcond(rest, env, mode, tr, prop)
    end
  end

  defp evprog([x], env, mode, tr, prop) do
    eval(x, env, mode, tr, prop)
  end

  defp evprog([x | xs], env, mode, tr, prop) do
    {_, env1, _, _} = eval(x, env, mode, tr, prop)
    evprog(xs, env1, mode, tr, prop)
  end

  defp make_nil([]) do
    []
  end

  defp make_nil([_ | xs]) do
    [nil | make_nil(xs)]
  end

  # sequential evlis
  defp evlis([], _, _, _) do
    []
  end

  defp evlis([x | xs], env, tr, prop) do
    {s, env, _, _} = eval(x, env, :seq, tr, prop)
    [s | evlis(xs, env, tr, prop)]
  end

  # parallel evlis
  defp paraevlis(x, env, tr, prop) do
    x1 = paraevlis1(x, env, tr, prop, 0)
    c = length(x) - length(x1)
    x2 = paraevlis2(c, [])

    (x1 ++ x2)
    |> Enum.sort()
    |> Enum.map(fn x -> Enum.at(x, 1) end)
  end

  defp paraevlis1([], _, _, _, _) do
    []
  end

  defp paraevlis1([x | xs], env, tr, prop, c) do
    if is_fun(x) do
      pid = spawn(Worker, :eval, [])
      send(pid, {self(), {c, x, env, tr, prop}})
      paraevlis1(xs, env, tr, prop, c + 1)
    else
      {s, _, _, _} = eval(x, env, :seq, tr, prop)
      [[c, s] | paraevlis1(xs, env, tr, prop, c + 1)]
    end
  end

  defp paraevlis2(0, res) do
    res
  end

  defp paraevlis2(c, res) do
    receive do
      {:answer, ls} ->
        paraevlis2(c - 1, [ls | res])
    end
  end

  @doc """
  iex>Eval.is_upper_atom(:A)
  true
  iex>Eval.is_upper_atom(:ABC)
  true
  iex>Eval.is_upper_atom(:Abc)
  false
  """
  def is_upper_atom(x) do
    Enum.all?(Atom.to_charlist(x), fn y -> y >= 65 && y <= 90 end)
  end

  def assoc(_, []) do
    nil
  end

  def assoc(x, [[x | y] | _]) do
    y
  end

  def assoc(x, [_ | y]) do
    assoc(x, y)
  end

  def pairlis([], _, env) do
    env
  end

  def pairlis([x | xs], [y | ys], env) do
    [[x | y] | pairlis(xs, ys, env)]
  end

  # ---------SUBR==================
  defp primitive([:car, arg], env, _, tr, prop) do
    if !is_list(arg) do
      Elxlisp.error("car not list", arg)
    end

    {hd(arg), env, tr, prop}
  end

  defp primitive([:car | arg], _, _, _, _) do
    Elxlisp.error("car argument error", arg)
  end

  defp primitive([:cdr, arg], env, _, tr, prop) do
    if !is_list(arg) do
      Elxlisp.error("cdr not list", arg)
    end

    {tl(arg), env, tr, prop}
  end

  defp primitive([:cdr | arg], _, _, _, _) do
    Elxlisp.error("cdr argument error", arg)
  end

  defp primitive([:cons, x, y], env, _, tr, prop) do
    {[x | y], env, tr, prop}
  end

  defp primitive([:cons | arg], _, _, _, _) do
    Elxlisp.error("cons argument error", arg)
  end

  defp primitive([:plus | args], env, _, tr, prop) do
    if Enum.any?(args, fn x -> !is_number(x) end) do
      Elxlisp.error("plus not number", args)
    end

    {args |> plus(), env, tr, prop}
  end

  defp primitive([:difference, x, y], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("difference not number", x)
    end

    if !is_number(y) do
      Elxlisp.error("difference not number", y)
    end

    {x - y, env, tr, prop}
  end

  defp primitive([:difference | arg], _, _, _, _) do
    Elxlisp.error("difference argument error", arg)
  end

  defp primitive([:times | args], env, _, tr, prop) do
    if Enum.any?(args, fn x -> !is_number(x) end) do
      Elxlisp.error("times not number", args)
    end

    {args |> times(), env, tr, prop}
  end

  defp primitive([:quotient, x, y], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("quotient not number", x)
    end

    if !is_number(y) do
      Elxlisp.error("quotient not number", y)
    end

    {div(x, y), env, tr, prop}
  end

  defp primitive([:quotient | arg], _, _, _, _) do
    Elxlisp.error("quotient argument error", arg)
  end

  defp primitive([:recip, x], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("difference not number", x)
    end

    {1 / x, env, tr, prop}
  end

  defp primitive([:recip | arg], _, _, _, _) do
    Elxlisp.error("recip argument error", arg)
  end

  defp primitive([:remainder, x, y], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("remainder not number", x)
    end

    if !is_number(y) do
      Elxlisp.error("remainder not number", y)
    end

    {rem(x, y), env, tr, prop}
  end

  defp primitive([:remainder | arg], _, _, _, _) do
    Elxlisp.error("remainder argument error", arg)
  end

  defp primitive([:divide, x, y], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("divide not number", x)
    end

    if !is_number(y) do
      Elxlisp.error("divide not number", y)
    end

    {[div(x, y), rem(x, y)], env, tr, prop}
  end

  defp primitive([:divide | arg], _, _, _, _) do
    Elxlisp.error("divide argument error", arg)
  end

  defp primitive([:expt, x, y], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("expt not number", x)
    end

    if !is_number(y) do
      Elxlisp.error("expt not number", y)
    end
    
    if is_float(x) || is_float(y) || y < 0 do 
      {:math.pow(x, y), env, tr, prop}
    else 
      {power(x,y), env, tr, prop}
    end
  end

  defp primitive([:expt | arg], _, _, _, _) do
    Elxlisp.error("expt argument error", arg)
  end

  defp primitive([:add1, x], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("add1 not number", x)
    end

    {x + 1, env, tr, prop}
  end

  defp primitive([:add1 | arg], _, _, _, _) do
    Elxlisp.error("add1 argument error", arg)
  end

  defp primitive([:sub1, x], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("sub1 not number", x)
    end

    {x - 1, env, tr, prop}
  end

  defp primitive([:sub1 | arg], _, _, _, _) do
    Elxlisp.error("sub1 argument error", arg)
  end

  defp primitive([:null, arg], env, _, tr, prop) do
    if arg == nil or arg == [] do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:null | arg], _, _, _, _) do
    Elxlisp.error("null argument error", arg)
  end

  defp primitive([:length, arg], env, _, tr, prop) do
    if !is_list(arg) do
      Elxlisp.error("list not list", arg)
    end

    {length(arg), env, tr, prop}
  end

  defp primitive([:length | arg], _, _, _, _) do
    Elxlisp.error("length argument error", arg)
  end

  defp primitive([:operate, op, x, y], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("operate not number", x)
    end

    if !is_number(y) do
      Elxlisp.error("operate not number", y)
    end

    cond do
      op == :+ -> {x + y, env, tr, prop}
      op == :- -> {x - y, env, tr, prop}
      op == :* -> {x * y, env, tr, prop}
      op == :/ -> {x / y, env, tr, prop}
    end
  end

  defp primitive([:operate | arg], _, _, _, _) do
    Elxlisp.error("operate argument error", arg)
  end

  defp primitive([:atom, arg], env, _, tr, prop) do
    if is_atom(arg) || is_number(arg) do
      {:t, env, tr, prop}
    else
      {nil, env.tr.prop}
    end
  end

  defp primitive([:eq, x, y], env, _, tr, prop) do
    if x == y do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:eq | arg], _, _, _, _) do
    Elxlisp.error("eq argument error", arg)
  end

  defp primitive([:equal, x, y], env, _, tr, prop) do
    if x == y do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:equql | arg], _, _, _, _) do
    Elxlisp.error("equal argument error", arg)
  end

  defp primitive([:greaterp, x, y], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("greaterp not number", x)
    end

    if !is_number(y) do
      Elxlisp.error("greaterp not number", y)
    end

    if x > y do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:greaterp | arg], _, _, _, _) do
    Elxlisp.error("greaterp argument error", arg)
  end

  defp primitive([:eqgreaterp, x, y], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("eqgreaterp not number", x)
    end

    if !is_number(y) do
      Elxlisp.error("eqgreaterp not number", y)
    end

    if x >= y do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:eqgreaterp | arg], _, _, _, _) do
    Elxlisp.error("eqgreaterp argument error", arg)
  end

  defp primitive([:lessp, x, y], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("lessp not number", x)
    end

    if !is_number(y) do
      Elxlisp.error("lessp not number", y)
    end

    if x < y do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:lessp | arg], _, _, _, _) do
    Elxlisp.error("lessp argument error", arg)
  end

  defp primitive([:eqlessp, x, y], env, _, tr, prop) do
    if !is_number(x) do
      Elxlisp.error("eqlessp not number", x)
    end

    if !is_number(y) do
      Elxlisp.error("eqlessp not number", y)
    end

    if x <= y do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:eqlessp | arg], _, _, _, _) do
    Elxlisp.error("eqlessp argument error", arg)
  end

  defp primitive([:max | arg], env, _, tr, prop) do
    if !Enum.all?(arg, fn x -> is_number(x) end) do
      Elxlisp.error("max not number", arg)
    end

    {Enum.max(arg), env, tr, prop}
  end

  defp primitive([:min | arg], env, _, tr, prop) do
    if !Enum.all?(arg, fn x -> is_number(x) end) do
      Elxlisp.error("min not number", arg)
    end

    {Enum.min(arg), env, tr, prop}
  end

  defp primitive([:logor | arg], env, _, tr, prop) do
    if !Enum.all?(arg, fn x -> is_integer(x) end) do
      Elxlisp.error("logor not number", arg)
    end

    {arg |> logor, env, tr, prop}
  end

  defp primitive([:logand | arg], env, _, tr, prop) do
    if !Enum.all?(arg, fn x -> is_integer(x) end) do
      Elxlisp.error("logand not number", arg)
    end

    {arg |> logand, env, tr, prop}
  end

  defp primitive([:logxor | arg], env, _, tr, prop) do
    if !Enum.all?(arg, fn x -> is_integer(x) end) do
      Elxlisp.error("logxor not number", arg)
    end

    {arg |> logxor, env, tr, prop}
  end

  defp primitive([:leftshift, x, n], env, _, tr, prop) do
    if !is_integer(x) do
      Elxlisp.error("lessp not number", x)
    end

    if !is_integer(n) do
      Elxlisp.error("lessp not number", n)
    end

    {leftshift(x, n), env, tr, prop}
  end

  defp primitive([:leftshift | arg], _, _, _, _) do
    Elxlisp.error("leftshift argument error", arg)
  end

  defp primitive([:numberp, arg], env, _, tr, prop) do
    if is_number(arg) do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:numberp | arg], _, _, _, _) do
    Elxlisp.error("numberp argument error", arg)
  end

  defp primitive([:floatp, arg], env, _, tr, prop) do
    if is_float(arg) do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:floatp | arg], _, _, _, _) do
    Elxlisp.error("floatp argument error", arg)
  end

  defp primitive([:zerop, arg], env, _, tr, prop) do
    if arg == 0 do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:zerop | arg], _, _, _, _) do
    Elxlisp.error("zerop argument error", arg)
  end

  defp primitive([:minusp, arg], env, _, tr, prop) do
    if arg < 0 do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:minusp | arg], _, _, _, _) do
    Elxlisp.error("zerop argument error", arg)
  end

  defp primitive([:onep, arg], env, _, tr, prop) do
    if arg == 1 do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:onep | arg], _, _, _, _) do
    Elxlisp.error("onep argument error", arg)
  end

  defp primitive([:listp, arg], env, _, tr, prop) do
    if is_list(arg) do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:listp | arg], _, _, _, _) do
    Elxlisp.error("listp argument error", arg)
  end

  defp primitive([:symbolp, arg], env, _, tr, prop) do
    if is_atom(arg) do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:symbolp | arg], _, _, _, _) do
    Elxlisp.error("symbolp argument error", arg)
  end

  defp primitive([:read], env, _, tr, prop) do
    {s, _} = Read.read([], :stdin)
    {s, env, tr, prop}
  end

  defp primitive([:eval, x, nil], _, mode, tr, prop) do
    eval(x, nil, mode, tr, prop)
  end

  defp primitive([:eval, x, y], _, mode, tr, prop) do
    eval(x, y, mode, tr, prop)
  end

  defp primitive([:eval | arg], _, _, _, _) do
    Elxlisp.error("eval argument error", arg)
  end

  defp primitive([:apply, f, a, e], _, mode, tr, prop) do
    funcall(f, a, e, mode, tr, prop)
  end

  defp primitive([:apply | arg], _, _, _, _) do
    Elxlisp.error("apply argument error", arg)
  end

  defp primitive([:print, x], env, _, tr, prop) do
    Print.print(x)
    {:t, env, tr, prop}
  end

  defp primitive([:print | arg], _, _, _, _) do
    Elxlisp.error("print argument error", arg)
  end

  defp primitive([:prin1, x], env, _, tr, prop) do
    Print.print1(x)
    {:t, env, tr, prop}
  end

  defp primitive([:prin1 | arg], _, _, _, _) do
    Elxlisp.error("prin1 argument error", arg)
  end

  defp primitive([:quit], _, _, _, _) do
    throw("goodbye")
  end

  defp primitive([:quit | arg], _, _, _, _) do
    Elxlisp.error("quit argument error", arg)
  end

  defp primitive([:reverse, x], env, _, tr, prop) do
    {Enum.reverse(x), env, tr, prop}
  end

  defp primitive([:reverse | arg], _, _, _, _) do
    Elxlisp.error("reverse argument error", arg)
  end

  defp primitive([:and | args], env, _, tr, prop) do
    if Enum.all?(args, fn x -> x != nil end) do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:or | args], env, _, tr, prop) do
    if Enum.any?(args, fn x -> x != nil end) do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:not, x], env, _, tr, prop) do
    if x == nil do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:not | arg], _, _, _, _) do
    Elxlisp.error("not argument error", arg)
  end

  defp primitive([:member, x, y], env, _, tr, prop) do
    if !is_list(y) do
      Elxlisp.error("member not list", y)
    end

    if Enum.member?(y, x) do
      {:t, env, tr, prop}
    else
      {nil, env, tr, prop}
    end
  end

  defp primitive([:member | arg], _, _, _, _) do
    Elxlisp.error("member argument error", arg)
  end

  defp primitive([:append, x, y], env, _, tr, prop) do
    if !is_list(x) and x != [] do
      Elxlisp.error("append not list", x)
    end

    if !is_list(y) and x != [] do
      Elxlisp.error("append not list", y)
    end

    {x ++ y, env, tr, prop}
  end

  defp primitive([:append | arg], _, _, _, _) do
    Elxlisp.error("append argument error", arg)
  end

  defp primitive([:maplist, f, l], env, _, tr, prop) do
    {maplist(f, l, env, tr, prop), env, tr, prop}
  end

  defp primitive([:maplist | arg], _, _, _, _) do
    Elxlisp.error("maplist argument error", arg)
  end

  defp primitive([:mapcar, f, l], env, _, tr, prop) do
    {mapcar(f, l, env, tr, prop), env, tr, prop}
  end

  defp primitive([:mapcar | arg], _, _, _, _) do
    Elxlisp.error("mapcar argument error", arg)
  end

  defp primitive([:compile, x], env, _, tr, prop) do
    name = String.split(x, ".") |> Enum.at(0)
    ext = String.split(x, ".") |> Enum.at(1)
    outfile = name <> ".o"
    {status, string} = File.read(x)

    if status == :error do
      throw("Error compile")
    end

    File.write(outfile, "defmodule Elxfunc do\n")

    cond do
      ext == "meta" or ext == nil ->
        File.write(outfile, Compile.is_compiled(:mexp, Read.tokenize(string)), [:append])

      ext == "lsp" ->
        File.write(outfile, Compile.is_compiled(:sexp, Read.stokenize(string)), [:append])
    end

    cond do
      ext == "meta" or ext == nil ->
        File.write(outfile, Compile.caller(:mexp, Read.tokenize(string), ""), [:append])

      ext == "lsp" ->
        File.write(outfile, Compile.caller(:sexp, Read.stokenize(string), ""), [:append])
    end

    cond do
      ext == "meta" or ext == nil ->
        File.write(outfile, Compile.compile(:mexp, Read.tokenize(string), ""), [:append])

      ext == "lsp" ->
        File.write(outfile, Compile.compile(:sexp, Read.stokenize(string), ""), [:append])
    end

    File.write(outfile, "end\n", [:append])
    {:t, env, tr, prop}
  end

  defp primitive([:compile | arg], _, _, _, _) do
    Elxlisp.error("compile argument error", arg)
  end

  defp primitive([:set, name, arg], env, _, tr, prop) do
    {name1, _, _, _} = name
    {s, _, _, _} = arg
    env1 = [[name1 | s] | env]
    {s, env1, tr, prop}
  end

  defp primitive([:putprop, x, y, z], env, _, tr, prop) do
    old = prop[x]

    if old == nil do
      dt = {x, [{y, z}]}
      prop1 = [dt | prop]
      {z, env, tr, prop1}
    else
      prop1 = Keyword.put(old, x, [{y, z} | old])
      {z, env, tr, prop1}
    end
  end

  defp primitive([:get, x, y], env, _, tr, prop) do
    dt = prop[x]
    val = dt[y]
    {val, env, tr, prop}
  end

  defp primitive(x, env, _, tr, prop) do
    {Elxfunc.primitive(x), env, tr, prop}
  end

  # ----------subr---------------
  defp load(env, []) do
    env
  end

  defp load(env, buf) do
    {s, buf1} = Read.read(buf, :filein)
    {_, env1, _, _} = Eval.eval(s, env, :seq, [], [])
    load(env1, buf1)
  end

  defp sload(env, []) do
    env
  end

  defp sload(env, buf) do
    {s, buf1} = Read.sread(buf, :filein)
    {_, env1, _, _} = Eval.eval(s, env, :seq, [], [])
    sload(env1, buf1)
  end

  # --------------- primitive -------------
  defp plus([]) do
    0
  end

  defp plus([x | xs]) do
    if !is_number(x) do
      throw("Error: Not number +")
    end

    x + plus(xs)
  end

  defp times([]) do
    1
  end

  defp times([x | xs]) do
    if !is_number(x) do
      throw("Error: Not number *")
    end

    x * times(xs)
  end

  defp power(_,0) do 1 end
  defp power(x,y) do
    if rem(y,2) == 0 do 
      power(x*x,div(y,2))
    else 
      x * power(x,y-1)
    end
  end

  defp logor([x, y]) do
    bor(x, y)
  end

  defp logor([x | xs]) do
    bor(x, logor(xs))
  end

  defp logand([x, y]) do
    band(x, y)
  end

  defp logand([x | xs]) do
    band(x, logand(xs))
  end

  defp logxor([x, y]) do
    bxor(x, y)
  end

  defp logxor([x | xs]) do
    bxor(x, logxor(xs))
  end

  defp leftshift(x, 0) do
    x
  end

  defp leftshift(x, n) when n > 0 do
    x <<< n
  end

  defp leftshift(x, n) when n < 0 do
    x >>> n
  end

  defp maplist(_, [], _, _, _) do
    []
  end

  defp maplist(f, [l | ls], env, tr, prop) do
    {s, _, _, _} = funcall(f, [[l | ls]], env, :seq, tr, prop)
    [s | maplist(f, ls, env, tr, prop)]
  end

  defp mapcar(_, [], _, _, _) do
    []
  end

  defp mapcar(f, [l | ls], env, tr, prop) do
    {s, _, _, _} = funcall(f, [l], env, :seq, tr, prop)
    [s | mapcar(f, ls, env, tr, prop)]
  end

  defp is_subr(x) do
    y = [
      :car,
      :cdr,
      :cons,
      :plus,
      :difference,
      :times,
      :quotient,
      :recip,
      :remainder,
      :divide,
      :expt,
      :add1,
      :sub1,
      :null,
      :length,
      :operate,
      :eq,
      :equal,
      :greaterp,
      :eqgreaterp,
      :lessp,
      :eqlessp,
      :max,
      :min,
      :logor,
      :logand,
      :leftshift,
      :numberp,
      :floatp,
      :onep,
      :zerop,
      :minusp,
      :listp,
      :symbolp,
      :read,
      :atom,
      :eval,
      :apply,
      :print,
      :prin1,
      :quit,
      :reverse,
      :and,
      :or,
      :not,
      :load,
      :member,
      :append,
      :maplist,
      :mapcar,
      :set,
      :putprop,
      :get,
      :compile
    ]

    Enum.member?(y, x)
  end

  # user defined function
  def is_fun(x) do
    if is_list(x) and !is_subr(Enum.at(x, 0)) do
      true
    else
      false
    end
  end
end
