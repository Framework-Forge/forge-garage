-- =========================================================
-- Forge GARAGE - TABELAS E TRIGGERS
-- Compatível com MariaDB 10.3
-- =========================================================


-- =========================================================
-- TABELA: police_impound
-- =========================================================

CREATE TABLE IF NOT EXISTS `police_impound` (
    `citizenid` varchar(50) NOT NULL,
    `plate` varchar(50) DEFAULT NULL,
    `vehicle` longtext DEFAULT NULL,
    `props` longtext DEFAULT NULL,
    `owner` longtext DEFAULT NULL,
    `officer` longtext DEFAULT NULL,
    `date` longtext NOT NULL,
    `fine` bigint(20) DEFAULT 0,
    `paid` tinyint(4) DEFAULT 0,
    `garage` longtext NOT NULL,
    KEY `idx_police_impound_plate` (`plate`),
    KEY `idx_police_impound_citizenid` (`citizenid`)
) ENGINE=InnoDB
DEFAULT CHARSET=utf8
COLLATE=utf8_general_ci;


-- =========================================================
-- TABELA: player_vehicles
-- Só será criada caso ainda não exista
-- =========================================================

CREATE TABLE IF NOT EXISTS `player_vehicles` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `license` varchar(50) DEFAULT NULL,
    `citizenid` varchar(50) DEFAULT NULL,
    `vehicle` varchar(50) DEFAULT NULL,
    `vehicle_name` longtext DEFAULT NULL,
    `hash` varchar(50) DEFAULT NULL,
    `mods` longtext DEFAULT NULL,
    `plate` varchar(50) NOT NULL,
    `fakeplate` varchar(50) DEFAULT NULL,
    `garage` varchar(50) DEFAULT NULL,
    `deformation` longtext DEFAULT NULL,
    `fuel` int(11) DEFAULT 100,
    `engine` float DEFAULT 1000,
    `body` float DEFAULT 1000,
    `state` int(11) DEFAULT 1,
    `depotprice` int(11) NOT NULL DEFAULT 0,
    `drivingdistance` int(50) DEFAULT NULL,
    `status` text DEFAULT NULL,
    `balance` int(11) NOT NULL DEFAULT 0,
    `paymentamount` int(11) NOT NULL DEFAULT 0,
    `paymentsleft` int(11) NOT NULL DEFAULT 0,
    `financetime` int(11) NOT NULL DEFAULT 0,

    PRIMARY KEY (`id`),

    KEY `idx_player_vehicles_plate` (`plate`),
    KEY `idx_player_vehicles_citizenid` (`citizenid`),
    KEY `idx_player_vehicles_license` (`license`)

) ENGINE=InnoDB
AUTO_INCREMENT=8
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci;


-- =========================================================
-- REMOVE TRIGGERS ANTIGOS
-- Isso evita erro caso eles já existam
-- =========================================================

DROP TRIGGER IF EXISTS `forge_garage_update_impound_plate`;

DROP TRIGGER IF EXISTS `forge_garage_delete_from_impound`;

DROP TRIGGER IF EXISTS `forge_garage_state_update`;


-- =========================================================
-- TRIGGER 1
-- Atualiza a placa no pátio quando a placa do veículo mudar
-- =========================================================

CREATE TRIGGER `forge_garage_update_impound_plate`
AFTER UPDATE ON `player_vehicles`
FOR EACH ROW
UPDATE `police_impound`
SET `plate` = NEW.`plate`
WHERE `plate` = OLD.`plate`
  AND NEW.`plate` <> OLD.`plate`;


-- =========================================================
-- TRIGGER 2
-- Remove o veículo do pátio quando ele for excluído
-- =========================================================

CREATE TRIGGER `forge_garage_delete_from_impound`
AFTER DELETE ON `player_vehicles`
FOR EACH ROW
DELETE FROM `police_impound`
WHERE `plate` = OLD.`plate`;


-- =========================================================
-- TRIGGER 3
-- Remove o veículo do pátio quando o state deixar de ser 2
-- state 2 normalmente representa veículo apreendido
-- =========================================================

CREATE TRIGGER `forge_garage_state_update`
AFTER UPDATE ON `player_vehicles`
FOR EACH ROW
DELETE FROM `police_impound`
WHERE NEW.`state` <> 2
  AND `plate` IN (OLD.`plate`, NEW.`plate`);


-- =========================================================
-- VERIFICAÇÃO
-- Exibe os triggers criados
-- =========================================================

SHOW TRIGGERS LIKE 'player_vehicles';