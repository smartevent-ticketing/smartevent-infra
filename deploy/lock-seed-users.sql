-- Run after Flyway finishes and before enabling the public Caddy profile.
-- V12 creates well-known demo credentials, including an administrator.
-- This script makes those exact seeded identities unusable on a public VPS.
DO $$
DECLARE
    locked_count integer;
BEGIN
    UPDATE users
    SET password_hash = crypt(encode(gen_random_bytes(32), 'hex'), gen_salt('bf')),
        status = 'DISABLED',
        updated_at = NOW()
    WHERE id IN (
        'a0000000-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000002',
        'c0000000-0000-0000-0000-000000000003'
    );
    GET DIAGNOSTICS locked_count = ROW_COUNT;
    IF locked_count <> 3 THEN
        RAISE EXCEPTION 'Expected 3 seeded users, found %; keep Caddy stopped', locked_count;
    END IF;
    RAISE NOTICE 'Locked all 3 seeded users';
END $$;
