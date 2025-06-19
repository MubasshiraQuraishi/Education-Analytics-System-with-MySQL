CREATE DATABASE education;
USE education;
SELECT * FROM dataa;
-- What are the top 5 most expensive programs by total cost?
EXPLAIN SELECT Program, SUM(Tuition + (Rent * duration) + (Insurance * duration) + visa_fee) AS total_Fees
FROM dataa
GROUP BY Program
ORDER BY total_fees DESC
LIMIT 5;

-- Which countries have the highest average tuition fees for Master's programs?
SELECT Country, ROUND(AVG(Tuition),2) as average_fees FROM dataa WHERE Levels = 'Master' GROUP BY Country ORDER BY 2 DESC LIMIT 1;

-- Find the average rent in cities with a Living_Cost_Index above the global average.
SELECT City, AVG(Rent) AS Average_rent FROM dataa WHERE living_Cost > (SELECT AVG(living_Cost) FROM dataa) GROUP BY 1 ORDER BY 2 DESC;

-- List universities offering PhD programs that have tuition fees below the average tuition of Master’s programs globally.
SELECT University FROM dataa
WHERE Levels = 'PhD' AND Tuition < (SELECT AVG(Tuition) FROM dataa WHERE Levels = 'Master');

-- Which cities offer programs with a rent lower than the median monthly rent of all cities?
SELECT City, Program, MAX(Rent) AS Median 
FROM (
		SELECT City, Program, Rent, NTILE(4) OVER(PARTITION BY City ORDER BY Rent) AS Quartile
        FROM dataa) X
WHERE Quartile = 2
GROUP BY 1, 2;

-- Create a CTE to find the yearly cost per program and rank programs within each country based on total yearly cost.
WITH CTE AS (
				SELECT City, Program, SUM(Tuition + Rent + Insurance  + visa_fee) AS yearly_cost
                FROM dataa
                GROUP BY 1, 2)
                
SELECT *, RANK() OVER(PARTITION BY City ORDER BY yearly_cost DESC) as Rnk
FROM CTE;

-- For each country, rank programs by tuition cost within each level (Undergraduate, Master’s, etc.)
SELECT Country, Levels, Program, RANK() OVER(PARTITION BY Country, Levels, Program ORDER BY Tuition ASC) as rnk
FROM dataa;

-- Show the percent difference in rent compared to the country average using window functions.
WITH CTE AS (
				SELECT Country, Rent, AVG(Rent) OVER(PARTITION BY Country) as avg_country_rent FROM dataa)
                
SELECT *, ROUND((Rent - avg_country_rent)/ avg_country_rent, 2) * 100 AS Percentage_diff
FROM CTE;
-- Extract and display only the type of degree from the Program column (e.g. “Computer”).
SELECT Program FROM dataa
WHERE Program LIKE '%Computer%';

-- Create a view for all programs in “Germany” with tuition under $20,000 and total yearly cost under $30,000.
CREATE VIEW German AS
SELECT Program FROM dataa WHERE Country = 'Germany' AND tuition <= 20000
GROUP BY Program
HAVING SUM(Tuition + Rent + Insurance  + visa_fee) < 30000;

SELECT * FROM German;

-- Create a temp table to store programs with duration more than 3 years and insurance above the average insurance.
CREATE TEMPORARY TABLE temp AS
SELECT Program FROM dataa
WHERE duration > 3 AND 	insurance > (SELECT AVG(insurance) FROM dataa);

SELECT * FROM temp;

-- Write a stored procedure that accepts a country and level as input and returns the top 3 cheapest programs in that category.
DROP PROCEDURE IF EXISTS pr_one;
DELIMITER $$
CREATE PROCEDURE pr_one(p_country VARCHAR(100), p_level VARCHAR(100))
BEGIN
	SELECT country, program, levels,
	       SUM(Tuition + Rent + Insurance + visa_fee) AS total_cost
	FROM dataa
	WHERE country = p_country AND levels = p_level
	GROUP BY country, program, levels
	ORDER BY total_cost DESC
	LIMIT 3;
END $$

DELIMITER ;
CALL pr_one('Germany', 'Master');

-- Create a stored procedure that updates rent based on an increase in Living_Cost_Index by 10% for a given city.
DROP PROCEDURE IF EXISTS pr_two;
DELIMITER $$
CREATE PROCEDURE pr_two(p_city VARCHAR(100))
BEGIN
	UPDATE dataa
    SET Living_cost = Living_cost * 0.10
    WHERE City = p_city;
END $$

CALL pr_two('Tokyo');

-- Create a function that takes program name and duration as input and returns the total estimated cost
DROP FUNCTION IF EXISTS estimated_cost;
DELIMITER $$
CREATE FUNCTION estimated_cost(p_program VARCHAR(20), p_duration INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
	DECLARE v_total DECIMAL(10, 2);
    SELECT SUM(Rent + Tuition + (Insurance * duration) + visa_fee)
    INTO v_total
    FROM dataa
    WHERE program = p_program AND duration = p_duration;
    
    RETURN IFNULL(v_total, 0);
    
END $$
SELECT estimated_cost('Data Science', 2);

DROP FUNCTION IF EXISTS pr_conversion;
DELIMITER $$
CREATE FUNCTION pr_conversion(p_tuition DECIMAL(10, 2), p_exchange_rate DOUBLE)
RETURNS DECIMAL(10, 2)
DETERMINISTIC
BEGIN
	RETURN  p_tuition * p_exchange_rate;
    
END $$

SELECT pr_conversion(156, 78);
-- Create a function that rates the Living_Cost_Index as 'Affordable' (below 50), 'Average' (50–75), or 'Expensive' (above 75).
DROP FUNCTION IF EXISTS fn_lcs;
DELIMITER $$
CREATE FUNCTION fn_lcs(p_living_cost DECIMAL(10,2))
RETURNS VARCHAR(20)
DETERMINISTIC
BEGIN
	RETURN CASE 
		WHEN p_living_cost < 50 THEN 'Affordable'
        WHEN p_living_cost < 75 THEN 'Average'
        ELSE 'Expensive'
	END;
END $$

SELECT City, Living_Cost, fn_lcs(Living_Cost) AS Cost_Label
FROM dataa;

--  Trigger that logs when a student program with high tuition is added
DELIMITER $$
CREATE TRIGGER program_alert
AFTER UPDATE ON dataa
FOR EACH ROW
BEGIN
	IF NEW.Tuition > 5000 THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'New Program is added with a high Tuition';
    END IF;
END $$
-- When a new university is inserted into the table, log the university name and timestamp into a separate audit table.
DELIMITER $$
CREATE TRIGGER new_uni
AFTER INSERT ON dataa
FOR EACH ROW
BEGIN
	INSERT INTO audit_table (university_name, date_added)
	VALUES (new.University, CURRENT_DATE());
END $$

-- Before inserting or updating a record, trigger should ensure Visa_Fee_USD is not negative or NULL — otherwise, prevent the action.
DELIMITER $$
CREATE TRIGGER visa_validator
BEFORE INSERT ON dataa
FOR EACH ROW
BEGIN
	IF NEW.Visa_fee < 1 THEN
		SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Visa fees cannot be negative or Null, check before inserting addtional data';
	END IF;
END $$

-- After an update, if tuition exceeds $100,000, set it back to $100,000 automatically using a trigger.
DELIMITER $$
CREATE TRIGGER fees_exceeds
BEFORE UPDATE ON dataa
FOR EACH ROW
BEGIN
	IF NEW.tuition > 10000 THEN
    SET NEW.tuition = 10000;
    END IF;
END $$

-- Before inserting, trigger should convert Program names to Title Case
DELIMITER $$
CREATE TRIGGER Capitalize
BEFORE INSERT ON dataa
FOR EACH ROW
BEGIN
	SET NEW.Program = UPPER(NEW.Program);
END $$

-- Prevent insertion of any program with Duration_Years less than 1 by raising an error.
DELIMITER $$
CREATE TRIGGER t_one
BEFORE INSERT ON dataa
FOR EACH ROW
BEGIN
	IF NEW.Duration < 1 THEN
		SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Program Duration should be atleast 1 year';
	END IF;
END $$


ALTER TABLE dataa MODIFY Country VARCHAR(100);
-- Optimizations
CREATE INDEX idx_tuition ON dataa(Country, Tuition);

-- Find the total number of universities in each country where the average tuition is above 10,000
EXPLAIN SELECT 
    Country,
    COUNT(DISTINCT University) AS total_uni,
    AVG(Tuition) AS avg_tuition
FROM dataa
GROUP BY Country
HAVING avg_tuition > 10000
ORDER BY avg_tuition DESC;

CREATE INDEX idx_program ON dataa(Program);

-- List all programs and their durations where the total cost exceeds 50,000, sorted by total cost.
WITH CTE AS (
				SELECT program, duration, SUM(Tuition + (Rent * duration) + Insurance + visa_fee) AS Total_cost
				FROM dataa
				GROUP BY program, duration
			)
SELECT * FROM CTE
WHERE total_cost > 50000
ORDER BY total_cost;

-- Display the top 5 most expensive universities (based on tuition) for programs longer than 2 years.
SELECT University, SUM(Tuition) as tuition_fees
FROM dataa
WHERE Duration > 2
GROUP BY University
ORDER BY tuition_fees DESC
LIMIT 5;
Another way
CREATE TEMPORARY TABLE tt_table AS 
				SELECT University, SUM(Tuition) as tuition_fees
				FROM dataa
				WHERE Duration > 2
				GROUP BY University
				ORDER BY tuition_fees DESC;
SELECT University FROM tt_table LIMIT 5;


CREATE FULLTEXT INDEX idx_search ON dataa(Program);
-- Retrieve all records where the program name contains the word "Engineering", and sort alphabetically by university name.
SELECT * FROM dataa
WHERE MATCH(Program) AGAINST('Engineering')
ORDER BY University ASC;

-- Get a count of programs grouped by program and duration where the number of such programs is more than 5.
WITH CTE AS (
				SELECT Program, duration, COUNT(Program) as total_programs FROM dataa
				GROUP BY program, duration
			)
SELECT * FROM CTE
WHERE total_programs > 5;