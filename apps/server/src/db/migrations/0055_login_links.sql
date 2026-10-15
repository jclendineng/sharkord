CREATE TABLE `login_links` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` integer NOT NULL,
	`secret_hash` text NOT NULL,
	`claim_key_hash` text,
	`status` text NOT NULL,
	`claimed_os` text,
	`claimed_device` text,
	`claimed_ip` text,
	`created_at` integer NOT NULL,
	`expires_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `login_links_user_idx` ON `login_links` (`user_id`);