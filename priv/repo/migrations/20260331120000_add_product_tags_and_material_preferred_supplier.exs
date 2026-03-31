defmodule Craftplan.Repo.Migrations.AddProductTagsAndMaterialPreferredSupplier do
  use Ecto.Migration

  def change do
    alter table(:catalog_products) do
      add :tags, {:array, :text}, null: false, default: []
    end

    alter table(:inventory_materials) do
      add :preferred_supplier_id,
          references(:inventory_suppliers, type: :uuid, on_delete: :nilify_all)
    end

    create index(:inventory_materials, [:preferred_supplier_id])
    create index(:catalog_products, [:tags], using: "GIN")
  end
end
