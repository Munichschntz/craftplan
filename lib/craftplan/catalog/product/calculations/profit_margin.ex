defmodule Craftplan.Catalog.Product.Calculations.ProfitMargin do
  @moduledoc false

  use Ash.Resource.Calculation

  alias Ash.NotLoaded
  alias Craftplan.DecimalHelpers
  alias Decimal, as: D

  @impl true
  def init(_opts), do: {:ok, []}

  @impl true
  def load(_query, _opts, _context), do: [:bom_unit_cost]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      price = DecimalHelpers.to_decimal(record.price)

      unit_cost =
        case record.bom_unit_cost do
          %NotLoaded{} -> D.new(0)
          nil -> D.new(0)
          value -> DecimalHelpers.to_decimal(value)
        end

      if D.compare(price, D.new(0)) == :gt do
        D.div(D.sub(price, unit_cost), price)
      else
        D.new(0)
      end
    end)
  end
end
