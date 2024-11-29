defmodule RuntimeCheck.Check do
  @moduledoc """
  Represents a system check.

  - name: The name of the check, an atom or string
  - checker: The function executed for the check, can be nil. It's a if the function returned `:ok`
  - nested_checks: A list of `Check` that are verified only if the `checker` returned `:ok`
  """

  require Logger

  @enforce_keys [:name]
  defstruct [:name, :checker, :nested_checks, :depth, :log]

  @type checker :: (-> :ok | {:ok, term()} | :ignore | {:error, term()})

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          checker: checker() | nil,
          nested_checks: [t()] | nil
        }

  @doc """
  Runs the given check(s). Logs the result of each check if `log` is true.
  """
  @spec run(t() | [t()], non_neg_integer(), boolean()) :: :ok | :error
  def run(check_or_checks, depth \\ 0, log \\ false)

  def run(%__MODULE__{} = check, depth, log) do
    nested_checks = check.nested_checks || []
    check = %{check | depth: depth, log: log, nested_checks: nested_checks}

    case execute_checker(check.checker) do
      :ok ->
        run_nested_checks(check)

      :ignore ->
        log(check, :warning, "ignored")
        :ok

      {:error, reason} ->
        log(check, :error, "failed. Reason: #{format_error(reason)}")
        :error
    end
  end

  def run(checks, depth, log) when is_list(checks) do
    results =
      Enum.map(checks, fn check ->
        run(check, depth, log)
      end)

    if Enum.any?(results, fn res -> res == :error end) do
      :error
    else
      :ok
    end
  end

  @spec execute_checker(nil | checker()) :: :ok | :ignore | {:error, term()}
  defp execute_checker(nil), do: :ok

  defp execute_checker(checker) when is_function(checker, 0) do
    case checker.() do
      :ok -> :ok
      {:ok, _} -> :ok
      :ignore -> :ignore
      {:error, _reason} = error -> error
    end
  catch
    kind, value ->
      {:error, {kind, value, __STACKTRACE__}}
  end

  @spec run_nested_checks(t()) :: :ok | :error
  defp run_nested_checks(%__MODULE__{nested_checks: []} = check) do
    log(check, :info, "passed")
    :ok
  end

  defp run_nested_checks(%__MODULE__{nested_checks: [_ | _], depth: depth} = check) do
    log(check, :info, "")

    case run(check.nested_checks, depth + 1, check.log) do
      :ok ->
        log(check, :info, "passed")
        :ok

      :error ->
        log(check, :error, "failed")
        :error
    end
  end

  @spec format_error(term()) :: String.t()
  defp format_error({kind, value, stacktrace}) when kind in [:error, :exit, :throw] do
    Exception.format(kind, value, stacktrace)
  end

  defp format_error(error), do: inspect(error)

  @spec log(t(), :info | :warning | :error, String.t()) :: :ok
  defp log(%__MODULE__{log: true, name: name, depth: depth}, level, msg) do
    spaces = if depth == 0, do: "", else: String.duplicate(">", depth) <> " "
    prefix = "[RuntimeCheck] #{spaces}#{name}"

    Logger.log(level, "#{prefix}: #{msg}")
  end

  defp log(%__MODULE__{}, _level, _msg), do: :ok
end