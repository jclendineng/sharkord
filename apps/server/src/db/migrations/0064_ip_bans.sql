CREATE TABLE `ip_bans` (
	`ip` text PRIMARY KEY NOT NULL,
	`user_id` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `ip_bans_user_idx` ON `ip_bans` (`user_id`);