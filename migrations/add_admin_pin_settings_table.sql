-- Create admin_pin_settings table for storing admin 4-digit PINs
-- Used for biometric + PIN login on subsequent app launches

CREATE TABLE IF NOT EXISTS admin_pin_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institute_id TEXT NOT NULL,
  admin_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pin_hash TEXT NOT NULL,  -- Hashed PIN (never store plaintext)
  pin_set_at TIMESTAMP WITH TIME ZONE NOT NULL,
  is_active BOOLEAN DEFAULT true,

  -- Track PIN changes
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),

  -- Unique constraint: One PIN per admin per institute
  UNIQUE(institute_id, admin_id),

  -- Index for faster lookups
  CONSTRAINT valid_institute_id CHECK (institute_id != ''),
  CONSTRAINT valid_admin_id CHECK (admin_id IS NOT NULL)
);

-- Create index for faster lookups by institute_id and admin_id
CREATE INDEX IF NOT EXISTS idx_admin_pin_settings_institute_admin
  ON admin_pin_settings(institute_id, admin_id);

-- Create index for institute_id lookups
CREATE INDEX IF NOT EXISTS idx_admin_pin_settings_institute
  ON admin_pin_settings(institute_id);

-- Create index for admin_id lookups
CREATE INDEX IF NOT EXISTS idx_admin_pin_settings_admin
  ON admin_pin_settings(admin_id);

-- Add RLS policies
ALTER TABLE admin_pin_settings ENABLE ROW LEVEL SECURITY;

-- Admins can only view/update their own PIN settings
CREATE POLICY "Admins can view their own PIN settings"
  ON admin_pin_settings
  FOR SELECT
  USING (admin_id = auth.uid());

CREATE POLICY "Admins can insert their own PIN settings"
  ON admin_pin_settings
  FOR INSERT
  WITH CHECK (admin_id = auth.uid());

CREATE POLICY "Admins can update their own PIN settings"
  ON admin_pin_settings
  FOR UPDATE
  USING (admin_id = auth.uid())
  WITH CHECK (admin_id = auth.uid());

-- Super admin can view all PIN settings (for audit)
CREATE POLICY "Super admin can view all PIN settings"
  ON admin_pin_settings
  FOR SELECT
  USING (
    (auth.jwt() ->> 'role') = 'super_admin'
  );
