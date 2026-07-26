BEGIN;
DELETE FROM public.admin_invites;


-- Total imported: 0
SELECT COUNT(*) as total_pending FROM public.admin_invites;
COMMIT;