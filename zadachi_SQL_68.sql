-- 432. «Клієнт із “перевернутим прайсом” (Upside-Down Pricing)»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,ROUND(sum(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND(((COUNT(order_id) OVER (partition by customer_id)::numeric) / 2),2) as middle_point 
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date, order_id) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC, order_id DESC) as rn_invert
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
	   ,case when rn = rn_invert THEN 0 ELSE 1 END as flag_null
FROm level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,ROUND(AVG(avg_price) FILTER (WHERE halfs = 'first')::numeric,2) as avg_price_first
	   ,ROUND(AVG(avg_price) FILTER (WHERE halfs = 'second')::numeric,2) as avg_price_second
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
FROM level2
WHERE flag_null = 1
GROUP BY customer_id)
SELECT *
FROm level3
WHERE avg_price_second < avg_price_first AND avg_chek_second > avg_chek_first

-- 433. «Клієнт з ефектом локального насичення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date, order_id) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date, order_id) as next_chek 
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > prev_chek AND sum_chek > next_chek THEN 1 ELSE 0 END as flag_chek
FROM level2
WHERE count_order >= 7),
level4 as(SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as real_count_order
FROM level3
WHERE prev_chek is not null AND next_chek is not null),
level5 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek 
FROM level4),
level6 as(SELECT *
       ,ROUND((sum_flag_chek::numeric / real_count_order::numeric),2) as ratio
FROM level5)
SELECT *
FROM level6
WHERE ratio >= 0.4 AND avg_chek > global_avg_chek

-- 434. «Клієнт із зламаною реакцією на обсяг»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by sum_chek) FROM level1) as median_chek
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date, order_id) as prev_quantity
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date, order_id) as prev_chek
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT *
       ,sum_quantity - prev_quantity as delta_quantity
	   ,sum_chek - prev_chek as delta_chek
FROm level3),
level5 as(SELECT *
       ,case when delta_quantity > 0 AND delta_chek <= 0 THEN 1 ELSE 0 END as flag_quantity_chek
FROM level4
WHERE prev_quantity is not null AND prev_chek is not null),
level6 as(SELECT *
       ,SUM(flag_quantity_chek) OVER (partition by customer_id) as sum_flag
	   ,COUNT(order_id) OVER (partition by customer_id) as real_count
FROM level5),
level7 as(SELECT *
       ,ROUND((sum_flag::numeric / real_count::numeric),2) as ratio
FROM level6)
SELECT *
FROm level7
WHERE ratio >= 0.5 AND avg_chek > median_chek 

-- 435. «Клієнт із ефектом зворотної стабілізації»

WITH block1 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date, order_id) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= 3 THEN 'early'
	   ELSE 'other' END as groups
FROM level1),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE groups = 'early')::numeric,2) as avg_chek_early
	   ,ROUND(AVG(sum_chek) FILTER (WHERE groups = 'other')::numeric,2) as avg_chek_other
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE groups = 'early')::numeric,2) as std_dev_chek_early
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE groups = 'other')::numeric,2) as std_dev_chek_other
FROm level2
GROUP BY customer_id)
SELECT *
       ,ROUND((std_dev_chek_early / avg_chek_early)::numeric,2) as cv_early
	   ,ROUND((std_dev_chek_other / avg_chek_other)::numeric,2) as cv_other
FROM level3),
block2 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as order_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(order_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_customer
	   ,ROUND(STDDEV(order_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek_customer
FROM level1),
level3 as(SELECT *
       ,ROUND((avg_chek_customer / std_dev_chek_customer)::numeric,2) as cv
FROM level2),
level4 as(SELECT DISTINCT customer_id, count_order
       ,cv
FROM level3)
SELECT *
       ,ROUND(AVG(cv) OVER ()::numeric,2) as global_cv
FROM level4)
SELECT *
FROM block1 
JOIn block2 USING (customer_id)
WHERE count_order >= 7
AND avg_chek_other > avg_chek_early
AND cv_other > cv_early
AND cv_early <= global_cv
AND cv_other >= global_cv

-- 436.«Клієнт із ефектом зламаного масштабу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),2) as middle_point
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by sum_quantity, order_id) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by  sum_quantity DESC, order_id DESC) as rn_invert
FROm level1),
level3 as(SELECT *
       ,ROUND((sum_chek / sum_quantity),2) as avg_price
	   ,case when rn = rn_invert THEN 0 ELSE 1 END as flag_null
FROm level2
WHERE count_order >= 6),
level4 as(SELECT *
       ,case when rn <= middle_point THEN 'low'
	   when rn > middle_point THEN 'high'
	   END as groups
FROM level3
WHERE flag_null = 1),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE groups = 'low')::numeric,2) as avg_chek_low
	   ,ROUND(AVG(sum_chek) FILTER (WHERE groups = 'high')::numeric,2) as avg_chek_high
	   ,ROUND(AVG(avg_price) FILTER (WHERE groups = 'low')::numeric,2) as avg_price_low
	   ,ROUND(AVG(avg_price) FILTER (WHERE groups = 'high')::numeric,2) as avg_price_high
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE groups = 'low')::numeric,2) as avg_quantity_low
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE groups = 'high')::numeric,2) as avg_quantity_high
FROm level4
GROUP By customer_id)
SELECT *
FROM level5
WHERE avg_chek_high > avg_chek_low
AND avg_price_high < avg_price_low
AND avg_quantity_high >= 1.5 * avg_quantity_low

-- 437. «Клієнт із ефектом зниклої знижки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as order_chek
	   ,ROUND(SUM(unit_price * quantity)::numeric,2) as gross
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date, order_id) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC, order_id DESC) as rn_invert
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(1 - (order_chek / gross)::numeric,2) as discount_rate_order
	   ,case when rn = rn_invert THEN 0 ELSE 1 END as flag_null
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level2
WHERE flag_null = 1),
level4 as(SELECT customer_id
       ,ROUND(AVG(discount_rate_order) FILTER (WHERE halfs = 'first')::numeric,2) as avg_discount_first
	   ,ROUND(AVG(discount_rate_order) FILTER (WHERE halfs = 'second')::numeric,2) as avg_discount_second
	   ,ROUND(AVG(order_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(order_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,ROUND(AVG(gross) FILTER (WHERE halfs = 'first')::numeric,2) as avg_gross_first
	   ,ROUND(AVG(gross) FILTER (WHERE halfs = 'second')::numeric,2) as avg_gross_second
FROM level3
GROUP By customer_id)
SELECT *
FROm level4
WHERE  avg_discount_second < avg_discount_first
AND (avg_chek_second / avg_chek_first) > (avg_gross_second / avg_gross_first)
AND avg_discount_first >= 0.05