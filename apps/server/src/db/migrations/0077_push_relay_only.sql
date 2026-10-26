-- devices registered straight with apple, which the server can no longer reach and would not
-- fit the table now that every device has a relay ticket
DELETE FROM `push_devices` WHERE `relay_ticket` IS NULL OR `encryption_key` IS NULL;--> statement-breakpoint
PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_push_devices` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`user_id` integer NOT NULL,
	`token` text NOT NULL,
	`token_version` integer NOT NULL,
	`session_id` text,
	`relay_ticket` text NOT NULL,
	`encryption_key` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`session_id`) REFERENCES `sessions`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
INSERT INTO `__new_push_devices`("id", "user_id", "token", "token_version", "session_id", "relay_ticket", "encryption_key", "created_at") SELECT "id", "user_id", "token", "token_version", "session_id", "relay_ticket", "encryption_key", "created_at" FROM `push_devices`;--> statement-breakpoint
DROP TABLE `push_devices`;--> statement-breakpoint
ALTER TABLE `__new_push_devices` RENAME TO `push_devices`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE UNIQUE INDEX `push_devices_token_idx` ON `push_devices` (`token`);--> statement-breakpoint
CREATE INDEX `push_devices_user_idx` ON `push_devices` (`user_id`);