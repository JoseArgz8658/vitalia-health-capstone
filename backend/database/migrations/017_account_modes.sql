-- Modos de sesión explícitos. Conservar role_code como dato legado, sin sustituirlo.
CREATE TABLE public.vitalia_account_roles (
 account_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 role_code text NOT NULL REFERENCES public.vitalia_roles(code),
 active boolean NOT NULL DEFAULT true,
 grant_source text NOT NULL CHECK(grant_source IN ('legacy','account_created','invitation_accepted')),
 invitation_id uuid REFERENCES public.vitalia_professional_invitations(id),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(account_id,role_code),
 CHECK((grant_source='invitation_accepted')=(invitation_id IS NOT NULL)),
 CHECK(grant_source<>'invitation_accepted' OR role_code='profesional')
);
INSERT INTO public.vitalia_account_roles(account_id,role_code,grant_source)
SELECT id,role_code,'legacy' FROM public.vitalia_accounts;
CREATE FUNCTION public.vitalia_seed_account_role() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.vitalia_account_roles(account_id,role_code,grant_source) VALUES(NEW.id,NEW.role_code,'account_created');
 RETURN NEW;
END;
$$;
CREATE TRIGGER vitalia_account_initial_role AFTER INSERT ON public.vitalia_accounts FOR EACH ROW EXECUTE FUNCTION public.vitalia_seed_account_role();
ALTER TABLE public.vitalia_sessions ADD COLUMN active_role text;
UPDATE public.vitalia_sessions s SET active_role=a.role_code FROM public.vitalia_accounts a WHERE a.id=s.account_id;
ALTER TABLE public.vitalia_sessions ALTER COLUMN active_role SET NOT NULL;
ALTER TABLE public.vitalia_sessions ADD CONSTRAINT vitalia_session_granted_role FOREIGN KEY(account_id,active_role) REFERENCES public.vitalia_account_roles(account_id,role_code);
