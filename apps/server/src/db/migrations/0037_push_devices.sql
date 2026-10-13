CREATE TABLE `push_devices` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`user_id` integer NOT NULL,
	`token` text NOT NULL,
	`token_version` integer NOT NULL,
	`sandbox` integer DEFAULT false NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `push_devices_token_idx` ON `push_devices` (`token`);--> statement-breakpoint
CREATE INDEX `push_devices_user_idx` ON `push_devices` (`user_id`);