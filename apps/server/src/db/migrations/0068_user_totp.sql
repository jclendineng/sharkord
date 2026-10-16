CREATE TABLE `user_totp` (
	`user_id` integer PRIMARY KEY NOT NULL,
	`secret` text NOT NULL,
	`last_step` integer DEFAULT 0 NOT NULL,
	`recovery_code_hashes` text DEFAULT '[]' NOT NULL,
	`enabled_at` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
