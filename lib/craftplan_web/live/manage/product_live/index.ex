defmodule CraftplanWeb.ProductLive.Index do
  @moduledoc false
  use CraftplanWeb, :live_view

  alias Craftplan.Catalog
  alias Craftplan.Catalog.Product.Photo

  @impl true
  def render(assigns) do
    assigns =
      assign_new(assigns, :breadcrumbs, fn -> [] end)

    ~H"""
    <.header>
      Products
      <:actions>
        <.form for={%{}} id="product-tag-filter-form" phx-change="filter_tag">
          <select
            name="tag"
            class="rounded-md border border-stone-300 bg-white px-2 py-1 text-sm text-stone-700"
          >
            <option value="">All tags</option>
            <option :for={tag <- @available_tags} value={tag} selected={tag == @selected_tag}>
              {tag}
            </option>
          </select>
        </.form>
        <.link patch={~p"/manage/products/new"}>
          <.button variant={:primary}>New Product</.button>
        </.link>
      </:actions>
    </.header>

    <.table
      id="products"
      rows={@streams.products}
      row_click={fn {_, product} -> JS.navigate(~p"/manage/products/#{product.sku}") end}
      row_id={fn {dom_id, _} -> dom_id end}
    >
      <:empty>
        <div class="block py-4 pr-6">
          <span class={["relative"]}>
            No products found
          </span>
        </div>
      </:empty>
      <:col :let={{_, product}} label="Name">
        <div class="flex items-center space-x-2">
          <img
            :if={product.featured_photo != nil}
            src={Photo.url({product.featured_photo, product}, :thumb, signed: true)}
            alt={product.name}
            class="h-5 w-5"
          />
          <span>
            {product.name}
          </span>
        </div>
      </:col>
      <:col :let={{_, product}} label="SKU">
        <.kbd>
          {product.sku}
        </.kbd>
      </:col>
      <:col :let={{_, product}} label="Status">
        <.badge
          text={product.status}
          colors={[
            {product.status,
             "#{product_status_color(product.status)} #{product_status_bg(product.status)}"}
          ]}
        />
      </:col>
      <:col :let={{_, product}} label="Price">
        {format_money(@settings.currency, product.price)}
      </:col>

      <:col :let={{_, product}} label="Materials cost">
        {format_money(@settings.currency, product.materials_cost)}
      </:col>

      <:col :let={{_, product}} label="Gross profit">
        {format_money(@settings.currency, product.gross_profit)}
      </:col>

      <:col :let={{_, product}} label="Profit margin">
        {format_percentage(product.profit_margin || Decimal.new(0))}%
      </:col>

      <:col :let={{_, product}} label="Tags">
        <span class="text-xs text-stone-600">{Enum.join(product.tags || [], ", ")}</span>
      </:col>

      <:action :let={{_, product}}>
        <.link
          phx-click={JS.push("delete", value: %{id: product.id}) |> hide("#product-#{product.id}")}
          data-confirm="Are you sure?"
        >
          <.button size={:sm} variant={:danger}>
            Delete
          </.button>
        </.link>
      </:action>
    </.table>

    <.modal
      :if={@live_action in [:new, :edit]}
      id="product-modal"
      show
      title={@page_title}
      on_cancel={JS.patch(~p"/manage/products")}
    >
      <.live_component
        module={CraftplanWeb.ProductLive.FormComponent}
        id={(@product && @product.id) || :new}
        title={@page_title}
        action={@live_action}
        product={@product}
        current_user={@current_user}
        settings={@settings}
        patch={~p"/manage/products"}
      />
    </.modal>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    results = load_products(socket.assigns[:current_user], nil)
    available_tags = extract_tags(results)

    socket =
      socket
      |> assign(:selected_tag, nil)
      |> assign(:available_tags, available_tags)
      |> assign(:breadcrumbs, [
        %{label: "Products", path: ~p"/manage/products", current?: true}
      ])
      |> stream(:products, results)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    selected_tag = normalize_tag(Map.get(params, "tag"))
    products = load_products(socket.assigns.current_user, selected_tag)

    socket =
      socket
      |> assign(:selected_tag, selected_tag)
      |> assign(:available_tags, extract_tags(load_products(socket.assigns.current_user, nil)))
      |> stream(:products, products, reset: true)
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Product")
    |> assign(:product, nil)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Catalog")
    |> assign(:product, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case id
         |> Catalog.get_product_by_id!(actor: socket.assigns.current_user)
         |> Catalog.destroy_product(actor: socket.assigns.current_user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Product deleted successfully")
         |> stream_delete(:products, %{id: id})}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Failed to delete product.")}
    end
  end

  @impl true
  def handle_event("filter_tag", %{"tag" => tag}, socket) do
    tag = normalize_tag(tag)

    to =
      if is_nil(tag) do
        ~p"/manage/products"
      else
        ~p"/manage/products?tag=#{tag}"
      end

    {:noreply, push_patch(socket, to: to)}
  end

  @impl true
  def handle_info({CraftplanWeb.ProductLive.FormComponent, {:saved, product}}, socket) do
    product =
      Ash.load!(product, [:materials_cost, :bom_unit_cost, :markup_percentage, :gross_profit, :profit_margin],
        actor: socket.assigns.current_user
      )

    socket =
      case socket.assigns.selected_tag do
        nil -> stream_insert(socket, :products, product)
        tag when tag in (product.tags || []) -> stream_insert(socket, :products, product)
        _ -> socket
      end

    {:noreply, socket}
  end

  defp load_products(actor, selected_tag) do
    products =
      Catalog.list_products!(
        actor: actor,
        page: [limit: 100],
        load: [
          :materials_cost,
          :bom_unit_cost,
          :markup_percentage,
          :gross_profit,
          :profit_margin
        ]
      )

    results =
      case products do
        %Ash.Page.Keyset{results: res} -> res
        %Ash.Page.Offset{results: res} -> res
        other -> other
      end

    case selected_tag do
      nil -> results
      tag -> Enum.filter(results, fn product -> tag in (product.tags || []) end)
    end
  end

  defp extract_tags(products) do
    products
    |> Enum.flat_map(fn product -> product.tags || [] end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_tag(nil), do: nil
  defp normalize_tag(""), do: nil

  defp normalize_tag(tag) do
    case String.trim(tag) do
      "" -> nil
      value -> value
    end
  end
end
