INSERT OR IGNORE INTO `role_permissions` (`role_id`, `permission`, `created_at`) SELECT `role_id`, 'PIN_DM_MESSAGES', unixepoch() FROM `role_permissions` WHERE `permission` = 'PIN_MESSAGES';
