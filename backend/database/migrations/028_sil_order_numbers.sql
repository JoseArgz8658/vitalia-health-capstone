-- Identificador correlativo solo para las órdenes del SIL.
ALTER TABLE public.vitalia_sil_orders ADD COLUMN order_number bigint;
CREATE SEQUENCE public.vitalia_sil_order_number_seq AS bigint START WITH 1;
ALTER TABLE public.vitalia_sil_orders
  ALTER COLUMN order_number SET DEFAULT nextval('public.vitalia_sil_order_number_seq'::regclass);
UPDATE public.vitalia_sil_orders
  SET order_number=nextval('public.vitalia_sil_order_number_seq'::regclass)
  WHERE order_number IS NULL;
ALTER TABLE public.vitalia_sil_orders ALTER COLUMN order_number SET NOT NULL;
ALTER TABLE public.vitalia_sil_orders ADD CONSTRAINT vitalia_sil_orders_order_number_unique UNIQUE(order_number);
ALTER SEQUENCE public.vitalia_sil_order_number_seq OWNED BY public.vitalia_sil_orders.order_number;
