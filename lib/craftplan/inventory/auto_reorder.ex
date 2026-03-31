defmodule Craftplan.Inventory.AutoReorder do
  @moduledoc false

  alias Craftplan.Inventory
  alias Decimal, as: D

  @spec maybe_create_for_material(binary(), any()) :: {:ok, :created | :skipped, map()}
  def maybe_create_for_material(material_id, actor) do
    material =
      Inventory.get_material_by_id!(material_id,
        actor: actor,
        load: [:current_stock, :preferred_supplier]
      )

    with true <- threshold_present?(material.minimum_stock),
         true <- has_preferred_supplier?(material),
         true <- below_threshold?(material),
         {:ok, needed_qty} <- remaining_needed_qty(material, actor),
         true <- D.compare(needed_qty, D.new(0)) == :gt do
      {:ok, po} =
        Inventory.create_purchase_order(
          %{supplier_id: material.preferred_supplier_id, ordered_at: DateTime.utc_now()},
          actor: actor
        )

      {:ok, _item} =
        Inventory.create_purchase_order_item(
          %{
            purchase_order_id: po.id,
            material_id: material.id,
            quantity: needed_qty,
            unit_price: material.price
          },
          actor: actor
        )

      {:ok, :created, %{purchase_order_id: po.id, quantity: needed_qty}}
    else
      _ -> {:ok, :skipped, %{}}
    end
  rescue
    _ -> {:ok, :skipped, %{}}
  end

  defp threshold_present?(nil), do: false
  defp threshold_present?(minimum_stock), do: D.compare(minimum_stock, D.new(0)) == :gt

  defp has_preferred_supplier?(material), do: not is_nil(material.preferred_supplier_id)

  defp below_threshold?(material) do
    current_stock = material.current_stock || D.new(0)
    minimum_stock = material.minimum_stock || D.new(0)
    D.compare(current_stock, minimum_stock) == :lt
  end

  defp remaining_needed_qty(material, actor) do
    open_items =
      Inventory.list_open_po_items_for_material!(%{material_id: material.id},
        actor: actor
      )

    on_order =
      Enum.reduce(open_items, D.new(0), fn item, acc ->
        D.add(acc, item.quantity || D.new(0))
      end)

    current_stock = material.current_stock || D.new(0)
    minimum_stock = material.minimum_stock || D.new(0)

    needed = D.sub(minimum_stock, D.add(current_stock, on_order))

    {:ok, if(D.compare(needed, D.new(0)) == :gt, do: needed, else: D.new(0))}
  end
end
