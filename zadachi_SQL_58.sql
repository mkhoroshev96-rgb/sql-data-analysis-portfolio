-- 366. «Замовлення з ефектом надлишкового складу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1)
SELECT *
FROm level2
WHERE sum_quantity > avg_quantity AND sum_chek < avg_chek

-- 367. «Замовлення з ефектом різкого охолодження»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LEAD(order_date) OVER (partition by customer_id order by order_date) as next_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders),
level2 as(SELECT *
       ,next_date - order_date as interval
FROM level1
WHERE count_order >= 4),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by interval) as median_interval
FROm level2
GROUP BY customer_id)
SELECT *
FROM level2
JOIN level3 USING (customer_id)
WHERE interval > median_interval

-- 368. «Замовлення з ефектом фальшивого масштабу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by avg_price) as median_price
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level1
GROUP BY customer_id)
SELECT *
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 4 AND sum_quantity > median_quantity AND avg_price < median_price

-- 369. «Замовлення з ефектом хибної стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level1
GROUP BY customer_id),
level3 as(SELECT *
       ,ROUND(ABS((median_quantity - sum_quantity) / median_quantity)::numeric,2) as ratio_quantity 
FROm level1
JOIN level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT customer_id
       ,percentile_cont(0.25) WITHIN GROUP (order by sum_chek) as percentile_25
FROm level3
GROUP By customer_id)
SELECT *
FROM level3
JOIN level4 USING (customer_id)
WHERE ratio_quantity <= 0.1 AND sum_chek < percentile_25

-- 370. «Парадокс локальної нормальності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,LEAD(sum_quantity) OVER (partition by customer_id order by order_date) as next_quantity
FROm level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,(sum_quantity + prev_quantity + next_quantity)/3 as local_avg_quantity
FROM level2),
level4 as(SELECT *
       ,ROUND(ABS((sum_quantity::numeric - local_avg_quantity::numeric) / local_avg_quantity::numeric),2) as diff_quantity
FROm level3),
level5 as(SELECT customer_id
       ,percentile_cont(0.75) WITHIN GROUP (order by sum_quantity) as percentile_75
FROm level4
GROUP By customer_id),
level6 as(SELECT *
FROm level4
JOIN level5 USING (customer_id))
SELECT *
FROm level6
WHERE diff_quantity is not null AND diff_quantity <= 0.15 AND sum_quantity > percentile_75

-- 371. «Ілюзія зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as gradation
FROm level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,gradation
	   ,percentile_cont(0.5) WITHIN GROUP (order by avg_price) as median_price
FROm level2
GROUP By customer_id, gradation),
level4 as(SELECT *
FROM level2
JOIN level3 USING (customer_id, gradation)),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = 'first_half')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = 'second_half')::numeric,2) as avg_quantity_second
	   ,AVG(median_price) FILTER (WHERE gradation = 'first_half') as median_price_first
	   ,AVG(median_price) FILTER (WHERE gradation = 'second_half') as median_price_second
FROM level4
GROUP By customer_id)
SELECT *
FROm level5
WHERE avg_quantity_second > avg_quantity_first AND median_price_first > median_price_second

-- 372. «Парадокс ефективності»

WITH level1 as(SELECT employee_id
       ,ship_country
	   ,order_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN employees USING (employee_id)
GROUP By employee_id, ship_country, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by ship_country)::numeric,2) as avg_chek_per_country
	   ,COUNT(ship_country) OVER (partition by employee_id,ship_country) as count_ship_country
FROm level1
ORDER BY employee_id, ship_country),
level3 as(SELECT employee_id
       ,COUNT(distinct ship_country) as count_unik_country
FROM level2
GROUP By employee_id),
level4 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by employee_id,ship_country)::numeric,2) as avg_chek_employee_country
FROM level2
JOIn level3 USING (employee_id)
WHERE count_ship_country > 1 AND count_unik_country > 2),
level5 as(SELECT *
       ,case when avg_chek_employee_country > avg_chek_per_country THEN 1 ELSE 0 END as flag_chek
	   ,COUNT (order_id) OVER (partition by employee_id) as count_order_employee_id
FROm level4),
level6 as(SELECT *
       ,SUM(flag_chek) OVER (partition by employee_id) as sum_flag_chek
FROm level5)
SELECT *
FROm level6
WHERE count_order_employee_id = sum_flag_chek

-- 373. «Ілюзія стабільності чеку»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,ROUND(AVG(avg_price) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_price_first
	   ,ROUND(AVG(avg_price) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_price_second
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_quantity_second
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_chek_second
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_second)::numeric,2) as diff_chek
FROm level3),
level5 as(SELECT *
       ,ROUND(ABS((avg_quantity_second - avg_quantity_first) / avg_quantity_second),2) as diff_quantity
	   ,ROUND(ABS((avg_price_second - avg_price_first) / avg_price_second),2) as diff_price
FROm level4
WHERE diff_chek <= 0.05)
SELECT *
FROM level5
WHERE diff_quantity >= 0.3 AND diff_price >= 0.3