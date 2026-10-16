-- the self updater is gone, so the permission that ran it grants nothing
DELETE FROM `role_permissions` WHERE `permission` = 'MANAGE_UPDATES';
