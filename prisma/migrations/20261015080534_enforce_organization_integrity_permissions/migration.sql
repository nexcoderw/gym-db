-- Organization integrity is enforced for every writer, including raw SQL clients.
-- This forward-only migration preserves existing records and global slug uniqueness.
ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_name_nonblank_check CHECK (
    char_length(btrim(name,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    )) > 0
  ),
  ADD CONSTRAINT organizations_slug_format_check CHECK (
    char_length(slug) BETWEEN 3 AND 63
    AND slug COLLATE "C" ~ '^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
  ),
  ADD CONSTRAINT organizations_slug_reserved_check CHECK (
    slug NOT IN (
      'admin', 'api', 'app', 'www', 'auth', 'login', 'member', 'members',
      'portal', 'dashboard', 'billing', 'support', 'status', 'static',
      'assets', 'cdn', 'mail', 'dev', 'staging', 'test', 'localhost',
      'account', 'accounts', 'oauth', 'console', 'internal', 'health',
      'metrics', 'production', 'development', 'bootstrap'
    )
  );

-- Runtime and test-role grants remain environment-specific and separately reviewed.
REVOKE ALL ON TABLE public.organizations FROM PUBLIC;
