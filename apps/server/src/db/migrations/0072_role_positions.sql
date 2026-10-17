ALTER TABLE `roles` ADD `position` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
CREATE INDEX `roles_position_idx` ON `roles` (`position`);--> statement-breakpoint
-- every existing role keeps the order it had, the order it was made in
UPDATE `roles` SET `position` = `id`;
