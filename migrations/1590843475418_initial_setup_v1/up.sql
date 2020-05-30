CREATE SCHEMA crm;
CREATE SCHEMA "deviceHub";
CREATE SCHEMA ingredient;
CREATE SCHEMA inventory;
CREATE SCHEMA master;
CREATE SCHEMA "onlineStore";
CREATE SCHEMA "order";
CREATE SCHEMA packaging;
CREATE SCHEMA safety;
CREATE SCHEMA settings;
CREATE SCHEMA "simpleRecipe";
CREATE SCHEMA unit;
CREATE TYPE public.summary AS (
	pending jsonb,
	underprocessing jsonb,
	readytodispatch jsonb,
	outfordelivery jsonb,
	delivered jsonb,
	rejectedcancelled jsonb
);
CREATE TABLE crm."orderCart" (
    id integer NOT NULL,
    "cartInfo" jsonb NOT NULL,
    "customerId" integer NOT NULL,
    "paymentMethodId" text,
    "paymentStatus" text DEFAULT 'PENDING'::text NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    "transactionId" text,
    "orderId" integer,
    created_at timestamp with time zone DEFAULT now(),
    "stripeCustomerId" text,
    "fulfillmentInfo" jsonb,
    tip numeric DEFAULT 0 NOT NULL,
    address jsonb,
    amount numeric,
    "transactionRemark" jsonb,
    "customerInfo" jsonb
);
CREATE FUNCTION crm.deliveryprice(ordercart crm."orderCart") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN 12.5;
END
$$;
CREATE FUNCTION crm.iscartvalid(ordercart crm."orderCart") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    IF JSONB_ARRAY_LENGTH(ordercart."cartInfo"->'products') = 0
        THEN RETURN json_build_object('status', false, 'error', 'No items in cart!');
    ELSIF ordercart."paymentMethodId" IS NULL OR ordercart."stripeCustomerId" IS NULL
        THEN RETURN json_build_object('status', false, 'error', 'No payment method selected!');
    ELSIF ordercart."address" IS NULL
        THEN RETURN json_build_object('status', false, 'error', 'No address selected!');
    ELSE
        RETURN json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION crm.itemtotal(ordercart crm."orderCart") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   total numeric := 0;
BEGIN
    -- FOR product IN SELECT * FROM json_array_elements(ordercart."cartInfo"->'products')
    -- LOOP
    --     IF product->'type' = 'comboProducts'
    --         THEN FOR subproduct IN product->'products' LOOP
    --             total := total + subproduct->'product'->'price'
    --         END LOOP;
    --     ELSE
    --         total := total + product->'price'
    --     END IF;
	   -- RAISE NOTICE 'Total: %', total;
    -- END LOOP;
    RETURN ordercart."cartInfo"->'total';
END
$$;
CREATE FUNCTION crm.tax(ordercart crm."orderCart") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   taxAmount numeric := 0;
   tax numeric;
   itemTotal numeric;
   deliveryPrice numeric;
   discount numeric := 0;
BEGIN
    SELECT crm.itemtotal(ordercart.*) into itemTotal;
    SELECT crm.deliveryprice(ordercart.*) into deliveryPrice;
    SELECT crm.taxpercent(ordercart.*) into tax;
    taxAmount := ROUND((itemTotal + deliveryPrice + ordercart.tip - discount) * (tax / 100), 2);
    RETURN taxAmount;
END
$$;
CREATE FUNCTION crm.taxpercent(ordercart crm."orderCart") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   tax numeric := 0;
BEGIN
    RETURN 2.5;
END
$$;
CREATE FUNCTION crm.totalprice(ordercart crm."orderCart") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   totalPrice numeric;
   tax numeric;
   itemTotal numeric;
   deliveryPrice numeric;
   discount numeric := 0;
BEGIN
    SELECT crm.itemtotal(ordercart.*) into itemTotal;
    SELECT crm.deliveryprice(ordercart.*) into deliveryPrice;
    SELECT crm.tax(ordercart.*) into tax;
    totalPrice := ROUND(itemTotal + deliveryPrice + ordercart.tip - discount + tax, 2);
    RETURN totalPrice;
END
$$;
CREATE TABLE ingredient.ingredient (
    id integer NOT NULL,
    name text NOT NULL,
    image text,
    "isPublished" boolean DEFAULT false NOT NULL,
    category text,
    "createdAt" date DEFAULT now()
);
CREATE FUNCTION ingredient.image_validity(ing ingredient.ingredient) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT NOT(ing.image IS NULL)
$$;
CREATE FUNCTION ingredient.imagevalidity(image ingredient.ingredient) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    SELECT NOT(image.image IS NULL)
$$;
CREATE FUNCTION ingredient.isingredientvalid(ingredient ingredient.ingredient) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    temp jsonb;
BEGIN
    SELECT * FROM ingredient."ingredientSachet" where "ingredientId" = ingredient.id LIMIT 1 into temp;
    IF temp IS NULL
        THEN return json_build_object('status', false, 'error', 'Not sachet present');
    ELSIF ingredient.category IS NULL
        THEN return json_build_object('status', false, 'error', 'Category not provided');
    ELSIF ingredient.image IS NULL OR LENGTH(ingredient.image) = 0
        THEN return json_build_object('status', true, 'error', 'Image not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE ingredient."modeOfFulfillment" (
    id integer NOT NULL,
    type text NOT NULL,
    "stationId" integer,
    "labelTemplateId" integer,
    "bulkItemId" integer,
    "isPublished" boolean DEFAULT false NOT NULL,
    priority integer NOT NULL,
    "ingredientSachetId" integer NOT NULL,
    "packagingId" integer,
    "isLive" boolean DEFAULT false NOT NULL,
    accuracy integer,
    "sachetItemId" integer
);
CREATE FUNCTION ingredient.ismodevalid(mode ingredient."modeOfFulfillment") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  temp json;
  isSachetValid boolean;
BEGIN
    SELECT ingredient.isSachetValid("ingredientSachet".*) 
        FROM ingredient."ingredientSachet"
        WHERE "ingredientSachet".id = mode."ingredientSachetId" into temp;
    SELECT temp->'status' into isSachetValid;
    IF NOT isSachetValid
        THEN return json_build_object('status', false, 'error', 'Sachet is not valid');
    ELSIF mode."stationId" IS NULL
        THEN return json_build_object('status', false, 'error', 'Station is not provided');
    ELSIF mode."bulkItemId" IS NULL AND mode."sachetItemId" IS NULL
        THEN return json_build_object('status', false, 'error', 'Item is not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE ingredient."ingredientSachet" (
    id integer NOT NULL,
    quantity numeric NOT NULL,
    "ingredientProcessingId" integer NOT NULL,
    "ingredientId" integer NOT NULL,
    "createdAt" timestamp with time zone DEFAULT now(),
    "updatedAt" timestamp with time zone DEFAULT now(),
    tracking boolean DEFAULT true NOT NULL,
    unit text NOT NULL,
    visibility boolean DEFAULT true NOT NULL,
    "liveMOF" integer,
    "defaultNutritionalValues" jsonb
);
CREATE FUNCTION ingredient.issachetvalid(sachet ingredient."ingredientSachet") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  temp json;
  isIngredientValid boolean;
BEGIN
    SELECT ingredient.isIngredientValid(ingredient.*) FROM ingredient.ingredient where ingredient.id = sachet."ingredientId" into temp;
    SELECT temp->'status' into isIngredientValid;
    IF NOT isIngredientValid
        THEN return json_build_object('status', false, 'error', 'Ingredient is not valid');
    ELSIF sachet."defaultNutritionalValues" IS NULL
        THEN return json_build_object('status', true, 'error', 'Default nutritional values not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE "simpleRecipe"."simpleRecipe" (
    id integer NOT NULL,
    author text,
    name jsonb NOT NULL,
    procedures jsonb,
    "assemblyStationId" integer,
    "cookingTime" text,
    utensils jsonb,
    description text,
    cuisine text,
    image text,
    show boolean DEFAULT true NOT NULL,
    assets jsonb,
    ingredients jsonb,
    type text,
    "isPublished" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION ingredient.issimplerecipevalid(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
BEGIN
    -- SELECT ingredient.isSachetValid("ingredientSachet".*) 
    --     FROM ingredient."ingredientSachet"
    --     WHERE "ingredientSachet".id = mode."ingredientSachetId" into temp;
    -- SELECT temp->'status' into isSachetValid;
    IF recipe.utensils IS NULL OR ARRAY_LENGTH(recipe.utensils) = 0
        THEN return json_build_object('status', false, 'error', 'Utensils not provided');
    ELSIF recipe.procedures IS NULL OR ARRAY_LENGTH(recipe.procedures) = 0
        THEN return json_build_object('status', false, 'error', 'Cooking steps are not provided');
    ELSIF recipe.ingredients IS NULL OR ARRAY_LENGTH(recipe.ingredients) = 0
        THEN return json_build_object('status', false, 'error', 'Ingrdients are not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION ingredient.sachetvalidity(sachet ingredient."ingredientSachet") RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT NOT(sachet.unit IS NULL OR sachet.quantity <= 0)
$$;
CREATE FUNCTION ingredient."set_current_timestamp_updatedAt"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updatedAt" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION ingredient.twiceq(sachet ingredient."ingredientSachet") RETURNS numeric
    LANGUAGE sql STABLE
    AS $$
  SELECT sachet.quantity*2
$$;
CREATE FUNCTION ingredient.validity(sachet ingredient."ingredientSachet") RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT NOT(sachet.unit IS NULL OR sachet.quantity <= 0)
$$;
CREATE FUNCTION inventory."set_current_timestamp_updatedAt"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updatedAt" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION inventory.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE TABLE "onlineStore"."comboProduct" (
    id integer NOT NULL,
    name jsonb NOT NULL,
    tags jsonb,
    description text,
    "isPublished" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION "onlineStore".iscomboproductvalid(product "onlineStore"."comboProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    temp int;
BEGIN
    SELECT COUNT(*) FROM "onlineStore"."comboProductComponent" where "comboProductComponent"."comboProductId" = product.id into temp;
    IF temp < 2
        THEN return json_build_object('status', false, 'error', 'Atleast 2 options required');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE "onlineStore"."customizableProduct" (
    id integer NOT NULL,
    name text NOT NULL,
    tags jsonb,
    description text,
    "default" integer,
    "isPublished" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION "onlineStore".iscustomizableproductvalid(product "onlineStore"."customizableProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    temp json;
BEGIN
    SELECT id FROM "onlineStore"."customizableProductOption" where "customizableProductOption"."customizableProductId" = product.id LIMIT 1 into temp;
    IF temp IS NULL
        THEN return json_build_object('status', false, 'error', 'No options provided');
    ELSIF product."default" IS NULL
        THEN return json_build_object('status', false, 'error', 'Default option not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE "onlineStore"."inventoryProduct" (
    id integer NOT NULL,
    "supplierItemId" integer,
    "sachetItemId" integer,
    accompaniments jsonb,
    "default" jsonb,
    "assemblyStationId" integer,
    name text,
    tags jsonb,
    description text,
    assets jsonb,
    "isPublished" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION "onlineStore".isinventoryproductvalid(product "onlineStore"."inventoryProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
BEGIN
    IF product."supplierItemId" IS NULL AND product."sachetItemId" IS NULL
        THEN return json_build_object('status', false, 'error', 'Item not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE "onlineStore"."menuCollection" (
    id integer NOT NULL,
    name text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    availability jsonb,
    "sortOrder" integer,
    categories jsonb,
    store jsonb,
    "isPublished" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION "onlineStore".ismenucollectionvalid(collection "onlineStore"."menuCollection") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    -- temp json;
    -- isSachetValid boolean;
BEGIN
    IF jsonb_array_length(collection.categories) = 0
        THEN return json_build_object('status', false, 'error', 'No categories provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE "onlineStore"."simpleRecipeProduct" (
    id integer NOT NULL,
    "simpleRecipeId" integer,
    name text NOT NULL,
    accompaniments jsonb,
    tags jsonb,
    description text,
    assets jsonb,
    "default" integer,
    "isPublished" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION "onlineStore".issimplerecipeproductvalid(product "onlineStore"."simpleRecipeProduct") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    temp json;
    isRecipeValid boolean;
BEGIN
    IF product."simpleRecipeId" IS NULL
        THEN return json_build_object('status', false, 'error', 'Recipe not provided');
    END IF;
    SELECT "simpleRecipe".isSimpleRecipeValid("simpleRecipe".*) FROM "simpleRecipe"."simpleRecipe" where "simpleRecipe".id = product."simpleRecipeId" into temp;
    SELECT temp->'status' into isRecipeValid;
    IF NOT isRecipeValid
        THEN return json_build_object('status', false, 'error', 'Recipe is invalid');
    ELSIF product."default" IS NULL
        THEN return json_build_object('status', false, 'error', 'Default option not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE "order"."order" (
    id oid NOT NULL,
    "customerId" integer NOT NULL,
    "orderStatus" text NOT NULL,
    "paymentStatus" text NOT NULL,
    "deliveryInfo" jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    "transactionId" text,
    tax double precision,
    discount numeric DEFAULT 0 NOT NULL,
    "itemTotal" numeric,
    "deliveryPrice" numeric,
    currency text DEFAULT 'usd'::text,
    updated_at timestamp with time zone DEFAULT now(),
    tip numeric
);
CREATE FUNCTION "order".ordersummary(order_row "order"."order") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    counts jsonb;
    amounts jsonb;
BEGIN
    SELECT json_object_agg(each."orderStatus", each."count") FROM (
        SELECT "orderStatus", COUNT (*) FROM "order"."order" GROUP BY "orderStatus"
    ) AS each into counts;
    SELECT json_object_agg(each."orderStatus", each."total") FROM (
        SELECT "orderStatus", SUM ("itemTotal") as total FROM "order"."order" GROUP BY "orderStatus"
    ) AS each into amounts;
	RETURN json_build_object('count', counts, 'amount', amounts);
END
$$;
CREATE FUNCTION "order".set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION public.fire() RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    return json_build_object('status', false, 'error', 'test');
END
$$;
CREATE FUNCTION public.image_validity(ing ingredient.ingredient) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT NOT(ing.image IS NULL)
$$;
CREATE FUNCTION public.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION safety.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION "simpleRecipe".issimplerecipevalid(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
BEGIN
    IF recipe.utensils IS NULL OR jsonb_array_length(recipe.utensils) = 0
        THEN return json_build_object('status', false, 'error', 'Utensils not provided');
    ELSIF recipe.procedures IS NULL OR jsonb_array_length(recipe.procedures) = 0
        THEN return json_build_object('status', false, 'error', 'Cooking steps are not provided');
    ELSIF recipe.ingredients IS NULL OR jsonb_array_length(recipe.ingredients) = 0
        THEN return json_build_object('status', false, 'error', 'Ingredients are not provided');
    ELSEIF recipe.image IS NULL OR LENGTH(recipe.image) = 0
        THEN return json_build_object('status', false, 'error', 'Image is not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE TABLE crm.customer (
    id integer NOT NULL,
    source text NOT NULL,
    email text NOT NULL,
    "keycloakId" text NOT NULL,
    "clientId" text
);
CREATE SEQUENCE crm.customer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm.customer_id_seq OWNED BY crm.customer.id;
CREATE SEQUENCE crm."orderCart_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE crm."orderCart_id_seq" OWNED BY crm."orderCart".id;
CREATE TABLE "deviceHub".computer (
    id integer NOT NULL,
    "printnodeId" text NOT NULL,
    state boolean NOT NULL,
    name text NOT NULL,
    "metaData" jsonb NOT NULL
);
CREATE SEQUENCE "deviceHub".computer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "deviceHub".computer_id_seq OWNED BY "deviceHub".computer.id;
CREATE TABLE "deviceHub"."kdsTerminal" (
    id integer NOT NULL
);
CREATE SEQUENCE "deviceHub"."kdsTerminal_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "deviceHub"."kdsTerminal_id_seq" OWNED BY "deviceHub"."kdsTerminal".id;
CREATE TABLE "deviceHub"."labelPrinter" (
    id integer NOT NULL,
    "printnodeId" text NOT NULL,
    state text NOT NULL,
    "computerId" integer NOT NULL
);
CREATE SEQUENCE "deviceHub"."labelPrinter_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "deviceHub"."labelPrinter_id_seq" OWNED BY "deviceHub"."labelPrinter".id;
CREATE TABLE "deviceHub"."labelTemplate" (
    id integer NOT NULL,
    name text NOT NULL
);
CREATE SEQUENCE "deviceHub"."labelTemplate_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "deviceHub"."labelTemplate_id_seq" OWNED BY "deviceHub"."labelTemplate".id;
CREATE TABLE "deviceHub"."receiptPrinter" (
    id integer NOT NULL,
    "computerId" integer NOT NULL
);
CREATE TABLE "deviceHub".scanner (
    id integer NOT NULL,
    "computerId" integer NOT NULL
);
CREATE SEQUENCE "deviceHub".scanner_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "deviceHub".scanner_id_seq OWNED BY "deviceHub".scanner.id;
CREATE TABLE "deviceHub".user_station (
    "userId" integer NOT NULL,
    "stationId" integer NOT NULL
);
CREATE TABLE "deviceHub"."weighingScale" (
    id integer NOT NULL,
    "computerId" integer NOT NULL
);
CREATE SEQUENCE "deviceHub"."weighingScale_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "deviceHub"."weighingScale_id_seq" OWNED BY "deviceHub"."weighingScale".id;
CREATE TABLE ingredient."ingredientProcessing" (
    id integer NOT NULL,
    "processingName" text NOT NULL,
    "ingredientId" integer NOT NULL
);
CREATE SEQUENCE ingredient."ingredientProcessing_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE ingredient."ingredientProcessing_id_seq" OWNED BY ingredient."ingredientProcessing".id;
CREATE SEQUENCE ingredient."ingredientSachet_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE ingredient."ingredientSachet_id_seq" OWNED BY ingredient."ingredientSachet".id;
CREATE SEQUENCE ingredient.ingredient_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE ingredient.ingredient_id_seq OWNED BY ingredient.ingredient.id;
CREATE TABLE ingredient."modeOfFulfillmentEnum" (
    value text NOT NULL,
    description text
);
CREATE SEQUENCE ingredient."modeOfFulfillment_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE ingredient."modeOfFulfillment_id_seq" OWNED BY ingredient."modeOfFulfillment".id;
CREATE TABLE inventory."bulkItemHistory" (
    id integer NOT NULL,
    "bulkItemId" integer NOT NULL,
    quantity numeric NOT NULL,
    comment jsonb,
    "purchaseOrderItemId" integer,
    "bulkWorkOrderId" integer,
    status text NOT NULL,
    unit text,
    "orderSachetId" integer,
    "sachetWorkOrderId" integer
);
CREATE SEQUENCE inventory."bulkHistory_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."bulkHistory_id_seq" OWNED BY inventory."bulkItemHistory".id;
CREATE TABLE inventory."bulkItem" (
    id integer NOT NULL,
    "processingName" text NOT NULL,
    "supplierItemId" integer NOT NULL,
    labor jsonb,
    "shelfLife" jsonb,
    yield jsonb,
    "nutritionInfo" jsonb,
    sop jsonb,
    allergens jsonb,
    "parLevel" numeric,
    "maxLevel" numeric,
    "onHand" numeric DEFAULT 0 NOT NULL,
    "storageCondition" jsonb,
    "createdAt" timestamp with time zone DEFAULT now(),
    "updatedAt" timestamp with time zone DEFAULT now(),
    image text,
    "bulkDensity" numeric DEFAULT 1,
    equipments jsonb,
    unit text,
    committed numeric DEFAULT 0 NOT NULL,
    awaiting numeric DEFAULT 0 NOT NULL,
    consumed numeric DEFAULT 0 NOT NULL,
    "isAvailable" boolean DEFAULT true NOT NULL
);
CREATE SEQUENCE inventory."bulkInventoryItem_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."bulkInventoryItem_id_seq" OWNED BY inventory."bulkItem".id;
CREATE TABLE inventory."bulkWorkOrder" (
    id integer NOT NULL,
    "inputBulkItemId" integer NOT NULL,
    "outputBulkItemId" integer NOT NULL,
    "outputQuantity" numeric NOT NULL,
    "userId" integer,
    "scheduledOn" timestamp with time zone,
    "inputQuantity" numeric NOT NULL,
    status text NOT NULL,
    "stationId" integer,
    "inputQuantityUnit" text
);
CREATE SEQUENCE inventory."bulkWorkOrder_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."bulkWorkOrder_id_seq" OWNED BY inventory."bulkWorkOrder".id;
CREATE TABLE inventory."purchaseOrderItem" (
    id integer NOT NULL,
    "bulkItemId" integer NOT NULL,
    "supplierItemId" integer NOT NULL,
    "orderQuantity" numeric NOT NULL,
    status text NOT NULL,
    details jsonb,
    unit text,
    "supplierId" integer NOT NULL
);
CREATE SEQUENCE inventory."purchaseOrder_bulkItemId_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."purchaseOrder_bulkItemId_seq" OWNED BY inventory."purchaseOrderItem"."bulkItemId";
CREATE SEQUENCE inventory."purchaseOrder_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."purchaseOrder_id_seq" OWNED BY inventory."purchaseOrderItem".id;
CREATE TABLE inventory."sachetItemHistory" (
    id integer NOT NULL,
    "sachetItemId" integer NOT NULL,
    "sachetWorkOrderId" integer,
    quantity numeric NOT NULL,
    comment jsonb,
    status text NOT NULL,
    "orderSachetId" integer,
    unit text
);
CREATE SEQUENCE inventory."sachetHistory_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."sachetHistory_id_seq" OWNED BY inventory."sachetItemHistory".id;
CREATE TABLE inventory."sachetItem" (
    id integer NOT NULL,
    "unitSize" numeric NOT NULL,
    "parLevel" numeric,
    "maxLevel" numeric,
    "onHand" numeric DEFAULT 0 NOT NULL,
    "isAvailable" boolean DEFAULT true NOT NULL,
    "bulkItemId" integer NOT NULL,
    unit text NOT NULL,
    consumed numeric DEFAULT 0 NOT NULL,
    awaiting numeric DEFAULT 0 NOT NULL,
    committed numeric DEFAULT 0 NOT NULL
);
CREATE SEQUENCE inventory."sachetItem2_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."sachetItem2_id_seq" OWNED BY inventory."sachetItem".id;
CREATE TABLE inventory."sachetWorkOrder" (
    id integer NOT NULL,
    "inputBulkItemId" integer NOT NULL,
    "outputSachetItemId" integer NOT NULL,
    "outputQuantity" numeric NOT NULL,
    "inputQuantity" numeric NOT NULL,
    "packagingId" integer,
    label jsonb,
    "stationId" integer,
    "userId" integer,
    "scheduledOn" timestamp with time zone,
    status text NOT NULL
);
CREATE SEQUENCE inventory."sachetWorkOrder_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."sachetWorkOrder_id_seq" OWNED BY inventory."sachetWorkOrder".id;
CREATE TABLE inventory.supplier (
    id integer NOT NULL,
    name text NOT NULL,
    "contactPerson" jsonb,
    address jsonb,
    "shippingTerms" jsonb,
    "paymentTerms" jsonb,
    available boolean DEFAULT true NOT NULL
);
CREATE TABLE inventory."supplierItem" (
    id integer NOT NULL,
    name text,
    "unitSize" integer,
    prices jsonb,
    "supplierId" integer,
    unit text,
    "leadTime" jsonb,
    certificates jsonb,
    "bulkItemAsShippedId" integer,
    sku text
);
CREATE SEQUENCE inventory."supplierItem_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."supplierItem_id_seq" OWNED BY inventory."supplierItem".id;
CREATE SEQUENCE inventory.supplier_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory.supplier_id_seq OWNED BY inventory.supplier.id;
CREATE TABLE inventory."unitConversionByBulkItem" (
    "bulkItemId" integer NOT NULL,
    "unitConversionId" integer NOT NULL,
    "customConversionFactor" numeric NOT NULL,
    id integer NOT NULL
);
CREATE SEQUENCE inventory."unitConversionByBulkItem_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inventory."unitConversionByBulkItem_id_seq" OWNED BY inventory."unitConversionByBulkItem".id;
CREATE TABLE master."accompanimentType" (
    id integer NOT NULL,
    name text NOT NULL
);
CREATE SEQUENCE master."accompanimentType_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE master."accompanimentType_id_seq" OWNED BY master."accompanimentType".id;
CREATE TABLE master."allergenName" (
    id integer NOT NULL,
    name text NOT NULL,
    description text
);
CREATE SEQUENCE master.allergen_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE master.allergen_id_seq OWNED BY master."allergenName".id;
CREATE TABLE master."cuisineName" (
    name text NOT NULL,
    id integer NOT NULL
);
CREATE SEQUENCE master."cuisineName_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE master."cuisineName_id_seq" OWNED BY master."cuisineName".id;
CREATE TABLE master."processingName" (
    id integer NOT NULL,
    name text NOT NULL,
    description text
);
CREATE SEQUENCE master.processing_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE master.processing_id_seq OWNED BY master."processingName".id;
CREATE TABLE "onlineStore".category (
    name text NOT NULL,
    id integer NOT NULL
);
CREATE SEQUENCE "onlineStore".category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore".category_id_seq OWNED BY "onlineStore".category.id;
CREATE TABLE "onlineStore"."comboProductComponent" (
    id integer NOT NULL,
    "simpleRecipeProductId" integer,
    "inventoryProductId" integer,
    "customizableProductId" integer,
    label text NOT NULL,
    "comboProductId" integer NOT NULL,
    discount numeric
);
CREATE SEQUENCE "onlineStore"."comboProductComponents_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore"."comboProductComponents_id_seq" OWNED BY "onlineStore"."comboProductComponent".id;
CREATE TABLE "onlineStore"."customizableProductOption" (
    id integer NOT NULL,
    "simpleRecipeProductId" integer,
    "inventoryProductId" integer,
    "customizableProductId" integer NOT NULL
);
CREATE SEQUENCE "onlineStore"."customizableProductOptions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore"."customizableProductOptions_id_seq" OWNED BY "onlineStore"."customizableProductOption".id;
CREATE TABLE "onlineStore"."inventoryProductOption" (
    id integer NOT NULL,
    quantity integer NOT NULL,
    label text,
    "inventoryProductId" integer NOT NULL,
    price jsonb NOT NULL
);
CREATE SEQUENCE "onlineStore"."inventoryProductOption_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore"."inventoryProductOption_id_seq" OWNED BY "onlineStore"."inventoryProductOption".id;
CREATE SEQUENCE "onlineStore"."inventoryProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore"."inventoryProduct_id_seq" OWNED BY "onlineStore"."inventoryProduct".id;
CREATE SEQUENCE "onlineStore"."menuCollection_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore"."menuCollection_id_seq" OWNED BY "onlineStore"."menuCollection".id;
CREATE SEQUENCE "onlineStore"."recipeProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore"."recipeProduct_id_seq" OWNED BY "onlineStore"."comboProduct".id;
CREATE TABLE "onlineStore"."simpleRecipeProductOption" (
    id integer NOT NULL,
    "simpleRecipeYieldId" integer NOT NULL,
    "simpleRecipeProductId" integer NOT NULL,
    type text NOT NULL,
    price jsonb NOT NULL,
    "isActive" boolean DEFAULT false NOT NULL
);
CREATE SEQUENCE "onlineStore"."simpleRecipeProductVariant_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore"."simpleRecipeProductVariant_id_seq" OWNED BY "onlineStore"."simpleRecipeProductOption".id;
CREATE SEQUENCE "onlineStore"."simpleRecipeProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore"."simpleRecipeProduct_id_seq" OWNED BY "onlineStore"."simpleRecipeProduct".id;
CREATE SEQUENCE "onlineStore"."smartProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "onlineStore"."smartProduct_id_seq" OWNED BY "onlineStore"."customizableProduct".id;
CREATE TABLE "order"."assemblyEnum" (
    value text NOT NULL,
    description text NOT NULL
);
CREATE TABLE "order"."orderInventoryProduct" (
    id integer NOT NULL,
    "orderId" integer NOT NULL,
    "inventoryProductId" integer NOT NULL,
    "assemblyStationId" integer,
    "assemblyStatus" text NOT NULL,
    "inventoryProductOptionId" integer NOT NULL,
    "comboProductId" integer,
    "comboProductComponentId" integer,
    "customizableProductId" integer,
    "customizableProductOptionId" integer
);
CREATE SEQUENCE "order"."orderInventoryProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "order"."orderInventoryProduct_id_seq" OWNED BY "order"."orderInventoryProduct".id;
CREATE TABLE "order"."orderMealKitProduct" (
    id integer NOT NULL,
    "orderId" integer NOT NULL,
    "simpleRecipeId" integer NOT NULL,
    "assemblyStationId" integer,
    "assemblyStatus" text NOT NULL,
    "recipeCardUri" text,
    "simpleRecipeProductId" integer NOT NULL,
    "comboProductId" integer,
    "comboProductComponentId" integer,
    "customizableProductId" integer,
    "customizableProductOptionId" integer,
    "simpleRecipeProductOptionId" integer NOT NULL
);
CREATE SEQUENCE "order"."orderItem_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "order"."orderItem_id_seq" OWNED BY "order"."orderMealKitProduct".id;
CREATE TABLE "order"."orderSachet" (
    id integer NOT NULL,
    "ingredientName" text NOT NULL,
    quantity numeric NOT NULL,
    unit text NOT NULL,
    "labelUri" text,
    "processingName" text NOT NULL,
    "bulkItemId" integer,
    "sachetItemId" integer,
    "ingredientSachetId" integer NOT NULL,
    "packingStationId" integer,
    status text NOT NULL,
    "isLabelled" boolean DEFAULT false NOT NULL,
    "isPortioned" boolean DEFAULT false NOT NULL,
    "packagingId" integer,
    "labelPrinterId" integer,
    accuracy text,
    "orderMealKitProductId" integer,
    "isAssembled" boolean DEFAULT false NOT NULL
);
CREATE SEQUENCE "order"."orderMealKitProductDetail_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "order"."orderMealKitProductDetail_id_seq" OWNED BY "order"."orderSachet".id;
CREATE TABLE "order"."orderPaymentStatusEnum" (
    value text NOT NULL,
    description text NOT NULL
);
CREATE TABLE "order"."orderReadyToEatProduct" (
    id integer NOT NULL,
    "orderId" integer NOT NULL,
    "simpleRecipeProductId" integer NOT NULL,
    "simpleRecipeId" integer NOT NULL,
    "simpleRecipeProductOptionId" integer NOT NULL,
    "comboProductId" integer,
    "comboProductComponentId" integer,
    "customizableProductId" integer,
    "customizableProductOptionId" integer,
    "assemblyStationId" integer,
    "assemblyStatus" text DEFAULT 'PENDING'::text NOT NULL
);
CREATE SEQUENCE "order"."orderReadyToEatProduct_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "order"."orderReadyToEatProduct_id_seq" OWNED BY "order"."orderReadyToEatProduct".id;
CREATE TABLE "order"."orderSachetStatusEnum" (
    value text NOT NULL,
    description text NOT NULL
);
CREATE TABLE "order"."orderStatusEnum" (
    value text NOT NULL,
    description text NOT NULL
);
CREATE SEQUENCE "order".order_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "order".order_id_seq OWNED BY "order"."order".id;
CREATE TABLE packaging.packaging (
    id integer NOT NULL,
    name text NOT NULL,
    sku text NOT NULL,
    "supplierId" integer NOT NULL,
    "unitPrice" numeric NOT NULL,
    "parLevel" integer NOT NULL,
    "maxLevel" integer NOT NULL,
    "onHand" integer NOT NULL,
    dimensions jsonb,
    "unitQuantity" numeric,
    "caseQuantity" numeric,
    "minOrderValue" numeric,
    "leadTime" jsonb,
    "isAvailable" boolean DEFAULT false NOT NULL,
    type text,
    awaiting numeric DEFAULT 0 NOT NULL,
    committed numeric DEFAULT 0 NOT NULL,
    consumed numeric DEFAULT 0 NOT NULL,
    "innWaterRes" boolean,
    "heatSafe" boolean,
    "outWaterRes" boolean,
    recyclable boolean,
    compostable boolean,
    "fdaComp" boolean,
    "innGreaseRes" boolean,
    "outGreaseRes" boolean,
    "leakResistance" jsonb,
    "packOpacity" jsonb,
    "compressableFrom" jsonb
);
CREATE SEQUENCE packaging.packaging_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE packaging.packaging_id_seq OWNED BY packaging.packaging.id;
CREATE TABLE safety."safetyCheck" (
    id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    "isVisibleOnStore" boolean NOT NULL
);
CREATE TABLE safety."safetyCheckPerUser" (
    id integer NOT NULL,
    "SafetyCheckId" integer NOT NULL,
    "userId" integer NOT NULL,
    "usesMask" boolean NOT NULL,
    "usesSanitizer" boolean NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    temperature numeric
);
CREATE SEQUENCE safety."safetyCheckByUser_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE safety."safetyCheckByUser_id_seq" OWNED BY safety."safetyCheckPerUser".id;
CREATE SEQUENCE safety."safetyCheck_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE safety."safetyCheck_id_seq" OWNED BY safety."safetyCheck".id;
CREATE TABLE settings.station (
    id integer NOT NULL,
    name text NOT NULL
);
CREATE SEQUENCE settings.station_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE settings.station_id_seq OWNED BY settings.station.id;
CREATE TABLE settings."user" (
    id integer NOT NULL,
    "firstName" text NOT NULL,
    "lastName" text NOT NULL
);
CREATE SEQUENCE settings.user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE settings.user_id_seq OWNED BY settings."user".id;
CREATE TABLE "simpleRecipe"."simpleRecipeYield" (
    id integer NOT NULL,
    "simpleRecipeId" integer NOT NULL,
    yield jsonb NOT NULL
);
CREATE SEQUENCE "simpleRecipe"."recipeServing_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "simpleRecipe"."recipeServing_id_seq" OWNED BY "simpleRecipe"."simpleRecipeYield".id;
CREATE TABLE "simpleRecipe"."simpleRecipeYield_ingredientSachet" (
    "recipeYieldId" integer NOT NULL,
    "ingredientSachetId" integer NOT NULL,
    "isVisible" boolean DEFAULT true NOT NULL,
    "slipName" text,
    "isSachetValid" boolean
);
CREATE SEQUENCE "simpleRecipe"."simpleRecipe_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "simpleRecipe"."simpleRecipe_id_seq" OWNED BY "simpleRecipe"."simpleRecipe".id;
CREATE TABLE unit.unit (
    id integer NOT NULL,
    name text NOT NULL
);
CREATE TABLE unit."unitConversion" (
    id integer NOT NULL,
    "inputUnitName" text NOT NULL,
    "outputUnitName" text NOT NULL,
    "defaultConversionFactor" jsonb
);
CREATE SEQUENCE unit."unitConversion_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE unit."unitConversion_id_seq" OWNED BY unit."unitConversion".id;
CREATE SEQUENCE unit.unit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE unit.unit_id_seq OWNED BY unit.unit.id;
ALTER TABLE ONLY crm.customer ALTER COLUMN id SET DEFAULT nextval('crm.customer_id_seq'::regclass);
ALTER TABLE ONLY crm."orderCart" ALTER COLUMN id SET DEFAULT nextval('crm."orderCart_id_seq"'::regclass);
ALTER TABLE ONLY "deviceHub".computer ALTER COLUMN id SET DEFAULT nextval('"deviceHub".computer_id_seq'::regclass);
ALTER TABLE ONLY "deviceHub"."kdsTerminal" ALTER COLUMN id SET DEFAULT nextval('"deviceHub"."kdsTerminal_id_seq"'::regclass);
ALTER TABLE ONLY "deviceHub"."labelPrinter" ALTER COLUMN id SET DEFAULT nextval('"deviceHub"."labelPrinter_id_seq"'::regclass);
ALTER TABLE ONLY "deviceHub"."labelTemplate" ALTER COLUMN id SET DEFAULT nextval('"deviceHub"."labelTemplate_id_seq"'::regclass);
ALTER TABLE ONLY "deviceHub".scanner ALTER COLUMN id SET DEFAULT nextval('"deviceHub".scanner_id_seq'::regclass);
ALTER TABLE ONLY "deviceHub"."weighingScale" ALTER COLUMN id SET DEFAULT nextval('"deviceHub"."weighingScale_id_seq"'::regclass);
ALTER TABLE ONLY ingredient.ingredient ALTER COLUMN id SET DEFAULT nextval('ingredient.ingredient_id_seq'::regclass);
ALTER TABLE ONLY ingredient."ingredientProcessing" ALTER COLUMN id SET DEFAULT nextval('ingredient."ingredientProcessing_id_seq"'::regclass);
ALTER TABLE ONLY ingredient."ingredientSachet" ALTER COLUMN id SET DEFAULT nextval('ingredient."ingredientSachet_id_seq"'::regclass);
ALTER TABLE ONLY ingredient."modeOfFulfillment" ALTER COLUMN id SET DEFAULT nextval('ingredient."modeOfFulfillment_id_seq"'::regclass);
ALTER TABLE ONLY inventory."bulkItem" ALTER COLUMN id SET DEFAULT nextval('inventory."bulkInventoryItem_id_seq"'::regclass);
ALTER TABLE ONLY inventory."bulkItemHistory" ALTER COLUMN id SET DEFAULT nextval('inventory."bulkHistory_id_seq"'::regclass);
ALTER TABLE ONLY inventory."bulkWorkOrder" ALTER COLUMN id SET DEFAULT nextval('inventory."bulkWorkOrder_id_seq"'::regclass);
ALTER TABLE ONLY inventory."purchaseOrderItem" ALTER COLUMN id SET DEFAULT nextval('inventory."purchaseOrder_id_seq"'::regclass);
ALTER TABLE ONLY inventory."sachetItem" ALTER COLUMN id SET DEFAULT nextval('inventory."sachetItem2_id_seq"'::regclass);
ALTER TABLE ONLY inventory."sachetItemHistory" ALTER COLUMN id SET DEFAULT nextval('inventory."sachetHistory_id_seq"'::regclass);
ALTER TABLE ONLY inventory."sachetWorkOrder" ALTER COLUMN id SET DEFAULT nextval('inventory."sachetWorkOrder_id_seq"'::regclass);
ALTER TABLE ONLY inventory.supplier ALTER COLUMN id SET DEFAULT nextval('inventory.supplier_id_seq'::regclass);
ALTER TABLE ONLY inventory."supplierItem" ALTER COLUMN id SET DEFAULT nextval('inventory."supplierItem_id_seq"'::regclass);
ALTER TABLE ONLY inventory."unitConversionByBulkItem" ALTER COLUMN id SET DEFAULT nextval('inventory."unitConversionByBulkItem_id_seq"'::regclass);
ALTER TABLE ONLY master."accompanimentType" ALTER COLUMN id SET DEFAULT nextval('master."accompanimentType_id_seq"'::regclass);
ALTER TABLE ONLY master."allergenName" ALTER COLUMN id SET DEFAULT nextval('master.allergen_id_seq'::regclass);
ALTER TABLE ONLY master."cuisineName" ALTER COLUMN id SET DEFAULT nextval('master."cuisineName_id_seq"'::regclass);
ALTER TABLE ONLY master."processingName" ALTER COLUMN id SET DEFAULT nextval('master.processing_id_seq'::regclass);
ALTER TABLE ONLY "onlineStore".category ALTER COLUMN id SET DEFAULT nextval('"onlineStore".category_id_seq'::regclass);
ALTER TABLE ONLY "onlineStore"."comboProduct" ALTER COLUMN id SET DEFAULT nextval('"onlineStore"."recipeProduct_id_seq"'::regclass);
ALTER TABLE ONLY "onlineStore"."comboProductComponent" ALTER COLUMN id SET DEFAULT nextval('"onlineStore"."comboProductComponents_id_seq"'::regclass);
ALTER TABLE ONLY "onlineStore"."customizableProduct" ALTER COLUMN id SET DEFAULT nextval('"onlineStore"."smartProduct_id_seq"'::regclass);
ALTER TABLE ONLY "onlineStore"."customizableProductOption" ALTER COLUMN id SET DEFAULT nextval('"onlineStore"."customizableProductOptions_id_seq"'::regclass);
ALTER TABLE ONLY "onlineStore"."inventoryProduct" ALTER COLUMN id SET DEFAULT nextval('"onlineStore"."inventoryProduct_id_seq"'::regclass);
ALTER TABLE ONLY "onlineStore"."inventoryProductOption" ALTER COLUMN id SET DEFAULT nextval('"onlineStore"."inventoryProductOption_id_seq"'::regclass);
ALTER TABLE ONLY "onlineStore"."menuCollection" ALTER COLUMN id SET DEFAULT nextval('"onlineStore"."menuCollection_id_seq"'::regclass);
ALTER TABLE ONLY "onlineStore"."simpleRecipeProduct" ALTER COLUMN id SET DEFAULT nextval('"onlineStore"."simpleRecipeProduct_id_seq"'::regclass);
ALTER TABLE ONLY "onlineStore"."simpleRecipeProductOption" ALTER COLUMN id SET DEFAULT nextval('"onlineStore"."simpleRecipeProductVariant_id_seq"'::regclass);
ALTER TABLE ONLY "order"."order" ALTER COLUMN id SET DEFAULT nextval('"order".order_id_seq'::regclass);
ALTER TABLE ONLY "order"."orderInventoryProduct" ALTER COLUMN id SET DEFAULT nextval('"order"."orderInventoryProduct_id_seq"'::regclass);
ALTER TABLE ONLY "order"."orderMealKitProduct" ALTER COLUMN id SET DEFAULT nextval('"order"."orderItem_id_seq"'::regclass);
ALTER TABLE ONLY "order"."orderReadyToEatProduct" ALTER COLUMN id SET DEFAULT nextval('"order"."orderReadyToEatProduct_id_seq"'::regclass);
ALTER TABLE ONLY "order"."orderSachet" ALTER COLUMN id SET DEFAULT nextval('"order"."orderMealKitProductDetail_id_seq"'::regclass);
ALTER TABLE ONLY packaging.packaging ALTER COLUMN id SET DEFAULT nextval('packaging.packaging_id_seq'::regclass);
ALTER TABLE ONLY safety."safetyCheck" ALTER COLUMN id SET DEFAULT nextval('safety."safetyCheck_id_seq"'::regclass);
ALTER TABLE ONLY safety."safetyCheckPerUser" ALTER COLUMN id SET DEFAULT nextval('safety."safetyCheckByUser_id_seq"'::regclass);
ALTER TABLE ONLY settings.station ALTER COLUMN id SET DEFAULT nextval('settings.station_id_seq'::regclass);
ALTER TABLE ONLY settings."user" ALTER COLUMN id SET DEFAULT nextval('settings.user_id_seq'::regclass);
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe" ALTER COLUMN id SET DEFAULT nextval('"simpleRecipe"."simpleRecipe_id_seq"'::regclass);
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield" ALTER COLUMN id SET DEFAULT nextval('"simpleRecipe"."recipeServing_id_seq"'::regclass);
ALTER TABLE ONLY unit.unit ALTER COLUMN id SET DEFAULT nextval('unit.unit_id_seq'::regclass);
ALTER TABLE ONLY unit."unitConversion" ALTER COLUMN id SET DEFAULT nextval('unit."unitConversion_id_seq"'::regclass);
ALTER TABLE ONLY crm.customer
    ADD CONSTRAINT "customer_dailyKeyUserId_key" UNIQUE ("keycloakId");
ALTER TABLE ONLY crm.customer
    ADD CONSTRAINT customer_email_key UNIQUE (email);
ALTER TABLE ONLY crm.customer
    ADD CONSTRAINT customer_id_key UNIQUE (id);
ALTER TABLE ONLY crm.customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY (id, "keycloakId");
ALTER TABLE ONLY crm."orderCart"
    ADD CONSTRAINT "orderCart_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "deviceHub".computer
    ADD CONSTRAINT computer_id_key UNIQUE (id);
ALTER TABLE ONLY "deviceHub".computer
    ADD CONSTRAINT computer_pkey PRIMARY KEY (id, "printnodeId");
ALTER TABLE ONLY "deviceHub".computer
    ADD CONSTRAINT "computer_printnodeId_key" UNIQUE ("printnodeId");
ALTER TABLE ONLY "deviceHub"."kdsTerminal"
    ADD CONSTRAINT "kdsTerminal_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "deviceHub"."labelPrinter"
    ADD CONSTRAINT "labelPrinter_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "deviceHub"."labelPrinter"
    ADD CONSTRAINT "labelPrinter_printnodeId_key" UNIQUE ("printnodeId");
ALTER TABLE ONLY "deviceHub"."labelTemplate"
    ADD CONSTRAINT "labelTemplate_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "deviceHub"."receiptPrinter"
    ADD CONSTRAINT "receiptPrinter_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "deviceHub".scanner
    ADD CONSTRAINT scanner_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "deviceHub".user_station
    ADD CONSTRAINT user_station_pkey PRIMARY KEY ("userId", "stationId");
ALTER TABLE ONLY "deviceHub"."weighingScale"
    ADD CONSTRAINT "weighingScale_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY ingredient."ingredientProcessing"
    ADD CONSTRAINT "ingredientProcessing_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY ingredient."ingredientSachet"
    ADD CONSTRAINT "ingredientSachet_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY ingredient.ingredient
    ADD CONSTRAINT ingredient_name_key UNIQUE (name);
ALTER TABLE ONLY ingredient.ingredient
    ADD CONSTRAINT ingredient_pkey PRIMARY KEY (id);
ALTER TABLE ONLY ingredient."modeOfFulfillmentEnum"
    ADD CONSTRAINT "modeOfFulfillmentEnum_pkey" PRIMARY KEY (value);
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkHistory_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."bulkItem"
    ADD CONSTRAINT "bulkInventoryItem_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrder_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."sachetItemHistory"
    ADD CONSTRAINT "sachetHistory_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."sachetItem"
    ADD CONSTRAINT "sachetItem2_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory."supplierItem"
    ADD CONSTRAINT "supplierItem_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY inventory.supplier
    ADD CONSTRAINT supplier_pkey PRIMARY KEY (id);
ALTER TABLE ONLY inventory."unitConversionByBulkItem"
    ADD CONSTRAINT "unitConversionByBulkItem_id_key" UNIQUE (id);
ALTER TABLE ONLY inventory."unitConversionByBulkItem"
    ADD CONSTRAINT "unitConversionByBulkItem_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY master."accompanimentType"
    ADD CONSTRAINT "accompanimentType_name_key" UNIQUE (name);
ALTER TABLE ONLY master."accompanimentType"
    ADD CONSTRAINT "accompanimentType_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY master."allergenName"
    ADD CONSTRAINT allergen_name_key UNIQUE (name);
ALTER TABLE ONLY master."allergenName"
    ADD CONSTRAINT allergen_pkey PRIMARY KEY (id);
ALTER TABLE ONLY master."cuisineName"
    ADD CONSTRAINT "cuisineName_id_key" UNIQUE (id);
ALTER TABLE ONLY master."cuisineName"
    ADD CONSTRAINT "cuisineName_name_key" UNIQUE (name);
ALTER TABLE ONLY master."cuisineName"
    ADD CONSTRAINT "cuisineName_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY master."processingName"
    ADD CONSTRAINT processing_name_key UNIQUE (name);
ALTER TABLE ONLY master."processingName"
    ADD CONSTRAINT processing_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "onlineStore".category
    ADD CONSTRAINT category_id_key UNIQUE (id);
ALTER TABLE ONLY "onlineStore".category
    ADD CONSTRAINT category_name_key UNIQUE (name);
ALTER TABLE ONLY "onlineStore".category
    ADD CONSTRAINT category_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "onlineStore"."comboProductComponent"
    ADD CONSTRAINT "comboProductComponents_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "onlineStore"."customizableProductOption"
    ADD CONSTRAINT "customizableProductOptions_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "onlineStore"."inventoryProductOption"
    ADD CONSTRAINT "inventoryProductOption_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "onlineStore"."inventoryProduct"
    ADD CONSTRAINT "inventoryProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "onlineStore"."menuCollection"
    ADD CONSTRAINT "menuCollection_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "onlineStore"."comboProduct"
    ADD CONSTRAINT "recipeProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "onlineStore"."simpleRecipeProductOption"
    ADD CONSTRAINT "simpleRecipeProductVariant_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "onlineStore"."simpleRecipeProduct"
    ADD CONSTRAINT "simpleRecipeProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "onlineStore"."customizableProduct"
    ADD CONSTRAINT "smartProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "order"."assemblyEnum"
    ADD CONSTRAINT "assemblyEnum_pkey" PRIMARY KEY (value);
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderItem_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderMealKitProductDetail_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "order"."orderPaymentStatusEnum"
    ADD CONSTRAINT "orderPaymentStatusEnum_pkey" PRIMARY KEY (value);
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "order"."orderSachetStatusEnum"
    ADD CONSTRAINT "orderSachetStatusEnum_pkey" PRIMARY KEY (value);
ALTER TABLE ONLY "order"."orderStatusEnum"
    ADD CONSTRAINT "orderStatusEnum_pkey" PRIMARY KEY (value);
ALTER TABLE ONLY "order"."order"
    ADD CONSTRAINT order_pkey PRIMARY KEY (id);
ALTER TABLE ONLY packaging.packaging
    ADD CONSTRAINT packaging_pkey PRIMARY KEY (id);
ALTER TABLE ONLY safety."safetyCheckPerUser"
    ADD CONSTRAINT "safetyCheckByUser_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY safety."safetyCheck"
    ADD CONSTRAINT "safetyCheck_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY settings.station
    ADD CONSTRAINT station_pkey PRIMARY KEY (id);
ALTER TABLE ONLY settings."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield"
    ADD CONSTRAINT "recipeServing_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet"
    ADD CONSTRAINT "recipeYield_ingredientSachet_pkey" PRIMARY KEY ("recipeYieldId", "ingredientSachetId");
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe"
    ADD CONSTRAINT "simpleRecipe_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY unit."unitConversion"
    ADD CONSTRAINT "unitConversion_pkey" PRIMARY KEY (id);
ALTER TABLE ONLY unit.unit
    ADD CONSTRAINT unit_name_key UNIQUE (name);
ALTER TABLE ONLY unit.unit
    ADD CONSTRAINT unit_pkey PRIMARY KEY (id);
CREATE TRIGGER "set_ingredient_ingredientSachet_updatedAt" BEFORE UPDATE ON ingredient."ingredientSachet" FOR EACH ROW EXECUTE FUNCTION ingredient."set_current_timestamp_updatedAt"();
COMMENT ON TRIGGER "set_ingredient_ingredientSachet_updatedAt" ON ingredient."ingredientSachet" IS 'trigger to set value of column "updatedAt" to current timestamp on row update';
CREATE TRIGGER "set_inventory_bulkItem_updatedAt" BEFORE UPDATE ON inventory."bulkItem" FOR EACH ROW EXECUTE FUNCTION inventory."set_current_timestamp_updatedAt"();
COMMENT ON TRIGGER "set_inventory_bulkItem_updatedAt" ON inventory."bulkItem" IS 'trigger to set value of column "updatedAt" to current timestamp on row update';
CREATE TRIGGER set_order_order_updated_at BEFORE UPDATE ON "order"."order" FOR EACH ROW EXECUTE FUNCTION "order".set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_order_order_updated_at ON "order"."order" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_safety_safetyCheck_updated_at" BEFORE UPDATE ON safety."safetyCheck" FOR EACH ROW EXECUTE FUNCTION safety.set_current_timestamp_updated_at();
COMMENT ON TRIGGER "set_safety_safetyCheck_updated_at" ON safety."safetyCheck" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
ALTER TABLE ONLY crm."orderCart"
    ADD CONSTRAINT "orderCart_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES crm.customer(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY crm."orderCart"
    ADD CONSTRAINT "orderCart_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub"."labelPrinter"
    ADD CONSTRAINT "labelPrinter_computerId_fkey" FOREIGN KEY ("computerId") REFERENCES "deviceHub".computer(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub"."receiptPrinter"
    ADD CONSTRAINT "receiptPrinter_computerId_fkey" FOREIGN KEY ("computerId") REFERENCES "deviceHub".computer(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".scanner
    ADD CONSTRAINT "scanner_computerId_fkey" FOREIGN KEY ("computerId") REFERENCES "deviceHub".computer(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".user_station
    ADD CONSTRAINT "user_station_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".user_station
    ADD CONSTRAINT "user_station_userId_fkey" FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub"."weighingScale"
    ADD CONSTRAINT "weighingScale_computerId_fkey" FOREIGN KEY ("computerId") REFERENCES "deviceHub".computer(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY ingredient."ingredientProcessing"
    ADD CONSTRAINT "ingredientProcessing_ingredientId_fkey" FOREIGN KEY ("ingredientId") REFERENCES ingredient.ingredient(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientProcessing"
    ADD CONSTRAINT "ingredientProcessing_processingName_fkey" FOREIGN KEY ("processingName") REFERENCES master."processingName"(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY ingredient."ingredientSachet"
    ADD CONSTRAINT "ingredientSachet_ingredientId_fkey" FOREIGN KEY ("ingredientId") REFERENCES ingredient.ingredient(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientSachet"
    ADD CONSTRAINT "ingredientSachet_ingredientProcessingId_fkey" FOREIGN KEY ("ingredientProcessingId") REFERENCES ingredient."ingredientProcessing"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientSachet"
    ADD CONSTRAINT "ingredientSachet_liveMOF_fkey" FOREIGN KEY ("liveMOF") REFERENCES ingredient."modeOfFulfillment"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."ingredientSachet"
    ADD CONSTRAINT "ingredientSachet_unit_fkey" FOREIGN KEY (unit) REFERENCES unit.unit(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_ingredientSachetId_fkey" FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_labelTemplateId_fkey" FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_sachetItemId_fkey" FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment"
    ADD CONSTRAINT "modeOfFulfillment_type_fkey" FOREIGN KEY (type) REFERENCES ingredient."modeOfFulfillmentEnum"(value) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_orderSachetId_fkey" FOREIGN KEY ("orderSachetId") REFERENCES "order"."orderSachet"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_purchaseOrderItemId_fkey" FOREIGN KEY ("purchaseOrderItemId") REFERENCES inventory."purchaseOrderItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_sachetWorkOrderId_fkey" FOREIGN KEY ("sachetWorkOrderId") REFERENCES inventory."sachetWorkOrder"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_unit_fkey" FOREIGN KEY (unit) REFERENCES unit.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory"
    ADD CONSTRAINT "bulkItemHistory_workOrderId_fkey" FOREIGN KEY ("bulkWorkOrderId") REFERENCES inventory."bulkWorkOrder"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem"
    ADD CONSTRAINT "bulkItem_processingName_fkey" FOREIGN KEY ("processingName") REFERENCES master."processingName"(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem"
    ADD CONSTRAINT "bulkItem_supplierItemId_fkey" FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem"
    ADD CONSTRAINT "bulkItem_unit_fkey" FOREIGN KEY (unit) REFERENCES unit.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_inputBulkItemId_fkey" FOREIGN KEY ("inputBulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_inputQuantityUnit_fkey" FOREIGN KEY ("inputQuantityUnit") REFERENCES unit.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_outputBulkItemId_fkey" FOREIGN KEY ("outputBulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder"
    ADD CONSTRAINT "bulkWorkOrder_userId_fkey" FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrderItem_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrderItem_supplierItemId_fkey" FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrderItem_supplier_fkey" FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem"
    ADD CONSTRAINT "purchaseOrderItem_unit_fkey" FOREIGN KEY (unit) REFERENCES unit.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItem"
    ADD CONSTRAINT "sachetItem2_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItem"
    ADD CONSTRAINT "sachetItem2_unit_fkey" FOREIGN KEY (unit) REFERENCES unit.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory"
    ADD CONSTRAINT "sachetItemHistory_orderSachetId_fkey" FOREIGN KEY ("orderSachetId") REFERENCES "order"."orderSachet"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory"
    ADD CONSTRAINT "sachetItemHistory_sachetItemId_fkey" FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory"
    ADD CONSTRAINT "sachetItemHistory_sachetWorkOrderId_fkey" FOREIGN KEY ("sachetWorkOrderId") REFERENCES inventory."sachetWorkOrder"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory"
    ADD CONSTRAINT "sachetItemHistory_unit_fkey" FOREIGN KEY (unit) REFERENCES unit.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_inputBulkItemId_fkey" FOREIGN KEY ("inputBulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_outputSachetItemId_fkey" FOREIGN KEY ("outputSachetItemId") REFERENCES inventory."sachetItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_stationId_fkey" FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder"
    ADD CONSTRAINT "sachetWorkOrder_userId_fkey" FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem"
    ADD CONSTRAINT "supplierItem_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem"
    ADD CONSTRAINT "supplierItem_unit_fkey" FOREIGN KEY (unit) REFERENCES unit.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."unitConversionByBulkItem"
    ADD CONSTRAINT "unitConversionByBulkItem_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY inventory."unitConversionByBulkItem"
    ADD CONSTRAINT "unitConversionByBulkItem_unitConversionId_fkey" FOREIGN KEY ("unitConversionId") REFERENCES unit."unitConversion"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "onlineStore"."comboProductComponent"
    ADD CONSTRAINT "comboProductComponent_comboProductId_fkey" FOREIGN KEY ("comboProductId") REFERENCES "onlineStore"."comboProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onlineStore"."comboProductComponent"
    ADD CONSTRAINT "comboProductComponent_customizableProductId_fkey" FOREIGN KEY ("customizableProductId") REFERENCES "onlineStore"."customizableProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onlineStore"."comboProductComponent"
    ADD CONSTRAINT "comboProductComponent_inventoryProductId_fkey" FOREIGN KEY ("inventoryProductId") REFERENCES "onlineStore"."inventoryProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onlineStore"."comboProductComponent"
    ADD CONSTRAINT "comboProductComponent_simpleRecipeProductId_fkey" FOREIGN KEY ("simpleRecipeProductId") REFERENCES "onlineStore"."simpleRecipeProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onlineStore"."customizableProductOption"
    ADD CONSTRAINT "customizableProductOption_customizableProductId_fkey" FOREIGN KEY ("customizableProductId") REFERENCES "onlineStore"."customizableProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onlineStore"."customizableProductOption"
    ADD CONSTRAINT "customizableProductOption_inventoryProductId_fkey" FOREIGN KEY ("inventoryProductId") REFERENCES "onlineStore"."inventoryProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onlineStore"."customizableProductOption"
    ADD CONSTRAINT "customizableProductOption_simpleRecipeProductId_fkey" FOREIGN KEY ("simpleRecipeProductId") REFERENCES "onlineStore"."simpleRecipeProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onlineStore"."customizableProduct"
    ADD CONSTRAINT "customizableProduct_default_fkey" FOREIGN KEY ("default") REFERENCES "onlineStore"."customizableProductOption"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY "onlineStore"."inventoryProductOption"
    ADD CONSTRAINT "inventoryProductOption_inventoryProductId_fkey" FOREIGN KEY ("inventoryProductId") REFERENCES "onlineStore"."inventoryProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onlineStore"."inventoryProduct"
    ADD CONSTRAINT "inventoryProduct_assemblyStationId_fkey" FOREIGN KEY ("assemblyStationId") REFERENCES settings.station(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY "onlineStore"."inventoryProduct"
    ADD CONSTRAINT "inventoryProduct_sachetItemId_fkey" FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY "onlineStore"."inventoryProduct"
    ADD CONSTRAINT "inventoryProduct_supplierItemId_fkey" FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY "onlineStore"."simpleRecipeProductOption"
    ADD CONSTRAINT "simpleRecipeProductOption_simpleRecipeProductId_fkey" FOREIGN KEY ("simpleRecipeProductId") REFERENCES "onlineStore"."simpleRecipeProduct"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onlineStore"."simpleRecipeProductOption"
    ADD CONSTRAINT "simpleRecipeProductOption_simpleRecipeYieldId_fkey" FOREIGN KEY ("simpleRecipeYieldId") REFERENCES "simpleRecipe"."simpleRecipeYield"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "onlineStore"."simpleRecipeProduct"
    ADD CONSTRAINT "simpleRecipeProduct_default_fkey" FOREIGN KEY ("default") REFERENCES "onlineStore"."simpleRecipeProductOption"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY "onlineStore"."simpleRecipeProduct"
    ADD CONSTRAINT "simpleRecipeProduct_simpleRecipeId_fkey" FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_assemblyStationId_fkey" FOREIGN KEY ("assemblyStationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_assemblyStatus_fkey" FOREIGN KEY ("assemblyStatus") REFERENCES "order"."assemblyEnum"(value) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_comboProductComponentId_fkey" FOREIGN KEY ("comboProductComponentId") REFERENCES "onlineStore"."comboProductComponent"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_comboProductId_fkey" FOREIGN KEY ("comboProductId") REFERENCES "onlineStore"."comboProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_customizableProductId_fkey" FOREIGN KEY ("customizableProductId") REFERENCES "onlineStore"."customizableProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_customizableProductOptionId_fkey" FOREIGN KEY ("customizableProductOptionId") REFERENCES "onlineStore"."customizableProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_inventoryProductId_fkey" FOREIGN KEY ("inventoryProductId") REFERENCES "onlineStore"."inventoryProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_inventoryProductOptionId_fkey" FOREIGN KEY ("inventoryProductOptionId") REFERENCES "onlineStore"."inventoryProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderInventoryProduct"
    ADD CONSTRAINT "orderInventoryProduct_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderItem_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderMealKitProductDetail_bulkItemId_fkey" FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderMealKitProductDetail_ingredientSachetId_fkey" FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_comboProductComponentId_fkey" FOREIGN KEY ("comboProductComponentId") REFERENCES "onlineStore"."comboProductComponent"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_comboProductId_fkey" FOREIGN KEY ("comboProductId") REFERENCES "onlineStore"."comboProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_customizableProductId_fkey" FOREIGN KEY ("customizableProductId") REFERENCES "onlineStore"."customizableProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_customizableProductOptionId_fkey" FOREIGN KEY ("customizableProductOptionId") REFERENCES "onlineStore"."customizableProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_simpleRecipeProductId_fkey" FOREIGN KEY ("simpleRecipeProductId") REFERENCES "onlineStore"."simpleRecipeProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderMealKitProduct_simpleRecipeProductOptionId_fkey" FOREIGN KEY ("simpleRecipeProductOptionId") REFERENCES "onlineStore"."simpleRecipeProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_assemblyStationId_fkey" FOREIGN KEY ("assemblyStationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_comboProductComponentId_fkey" FOREIGN KEY ("comboProductComponentId") REFERENCES "onlineStore"."comboProductComponent"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_comboProductId_fkey" FOREIGN KEY ("comboProductId") REFERENCES "onlineStore"."comboProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_customizableProductId_fkey" FOREIGN KEY ("customizableProductId") REFERENCES "onlineStore"."customizableProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_customizableProductOptionId_fkey" FOREIGN KEY ("customizableProductOptionId") REFERENCES "onlineStore"."customizableProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_simpleRecipeId_fkey" FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_simpleRecipeProductId_fkey" FOREIGN KEY ("simpleRecipeProductId") REFERENCES "onlineStore"."simpleRecipeProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderReadyToEatProduct"
    ADD CONSTRAINT "orderReadyToEatProduct_simpleRecipeProductOptionId_fkey" FOREIGN KEY ("simpleRecipeProductOptionId") REFERENCES "onlineStore"."simpleRecipeProductOption"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_labelPrinterId_fkey" FOREIGN KEY ("labelPrinterId") REFERENCES "deviceHub"."labelPrinter"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_orderMealKitProductId_fkey" FOREIGN KEY ("orderMealKitProductId") REFERENCES "order"."orderMealKitProduct"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_packagingId_fkey" FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_sachetItemId_fkey" FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_status_fkey" FOREIGN KEY (status) REFERENCES "order"."orderSachetStatusEnum"(value) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderSachet"
    ADD CONSTRAINT "orderSachet_unit_fkey" FOREIGN KEY (unit) REFERENCES unit.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderSimpleRecipeProduct_assemblyStationId_fkey" FOREIGN KEY ("assemblyStationId") REFERENCES settings.station(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."orderMealKitProduct"
    ADD CONSTRAINT "orderSimpleRecipeProduct_assemblyStatus_fkey" FOREIGN KEY ("assemblyStatus") REFERENCES "order"."assemblyEnum"(value) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."order"
    ADD CONSTRAINT "order_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES crm.customer(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "order"."order"
    ADD CONSTRAINT "order_orderStatus_fkey" FOREIGN KEY ("orderStatus") REFERENCES "order"."orderStatusEnum"(value) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY packaging.packaging
    ADD CONSTRAINT "packaging_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY safety."safetyCheckPerUser"
    ADD CONSTRAINT "safetyCheckByUser_SafetyCheckId_fkey" FOREIGN KEY ("SafetyCheckId") REFERENCES safety."safetyCheck"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY safety."safetyCheckPerUser"
    ADD CONSTRAINT "safetyCheckByUser_userId_fkey" FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet"
    ADD CONSTRAINT "simpleRecipeYield_ingredientSachet_ingredientSachetId_fkey" FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet"
    ADD CONSTRAINT "simpleRecipeYield_ingredientSachet_recipeYieldId_fkey" FOREIGN KEY ("recipeYieldId") REFERENCES "simpleRecipe"."simpleRecipeYield"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield"
    ADD CONSTRAINT "simpleRecipeYield_simpleRecipeId_fkey" FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe"
    ADD CONSTRAINT "simpleRecipe_assemblyStationId_fkey" FOREIGN KEY ("assemblyStationId") REFERENCES settings.station(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe"
    ADD CONSTRAINT "simpleRecipe_cuisine_fkey" FOREIGN KEY (cuisine) REFERENCES master."cuisineName"(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY unit."unitConversion"
    ADD CONSTRAINT "unitConversion_inputUnit_fkey" FOREIGN KEY ("inputUnitName") REFERENCES unit.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY unit."unitConversion"
    ADD CONSTRAINT "unitConversion_outputUnit_fkey" FOREIGN KEY ("outputUnitName") REFERENCES unit.unit(name) ON UPDATE RESTRICT ON DELETE RESTRICT;
