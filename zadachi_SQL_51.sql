-- 321. стабільність купівельної поведінки клієнта

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level2
GROUP BY customer_id, halfs),
level4 as(SELECT *
FROM level2
JOIN level3 USING(customer_id, halfs)),
level5 as(SELECT customer_id
       ,AVG(median_quantity) FILTER (WHERE halfs = 'first_half') as median_quantity_first
	   ,AVG(median_quantity) FILTER (WHERE halfs = 'second_half') as median_quantity_second
FROM level4
GROUP BY customer_id),
level6 as(SELECT *
       ,ROUND(ABS((median_quantity_second - median_quantity_first) / median_quantity_first)::numeric,2) as ratio
FROM level5)
SELECT *
FROM level6
WHERE ratio <= 0.1

-- 2 спосіб

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2)::numeric,2) as middle_point
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level2
GROUP BY customer_id, halfs),
level4 as(SELECT *
FROM level2
JOIN level3 USING(customer_id, halfs)),
level5 as(SELECT customer_id
       ,AVG(median_quantity) FILTER (WHERE halfs = 'first_half') as median_quantity_first
	   ,AVG(median_quantity) FILTER (WHERE halfs = 'second_half') as median_quantity_second
FROM level4
GROUP BY customer_id),
level6 as(SELECT *
       ,ROUND(ABS((median_quantity_second - median_quantity_first) / median_quantity_first)::numeric,2) as ratio
FROM level5)
SELECT *
FROM level6
WHERE ratio <= 0.1

-- 322. Як відрізняється дробовий мідл_поінт від цілочисельного

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point_first
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2)::numeric,2) as middle_point_second
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date)
SELECT *
FROM level1
WHERE middle_point_first <> middle_point_second

-- 323. нестабільність структури замовлення, а не обсягу

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2)::numeric,2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id,order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,order_id
	   ,COUNT(*) as count_item_in_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level4 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level2
JOIN level3 USING(customer_id, order_id)),
level5 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
	   ,percentile_cont(0.5) WITHIN GROUP (order by count_item_in_order) as median_count_item
FROM level4
GROUP BY customer_id, halfs),
level6 as(SELECT customer_id
       ,AVG(median_quantity) FILTER (WHERE halfs = 'first_half') as median_quantity_first
	   ,AVG(median_quantity) FILTER (WHERE halfs = 'second_half') as median_quantity_second
	   ,AVG(median_count_item) FILTER (WHERE halfs = 'first_half') as median_count_item_first
	   ,AVG(median_count_item) FILTER (WHERE halfs = 'second_half') as median_count_item_second
FROM level4
JOIN level5 USING(customer_id,halfs)
GROUP By customer_id),
level7 as(SELECT *
       ,ROUND((ABS(median_quantity_second - median_quantity_first) / median_quantity_first)::numeric,2) as ratio_quantity
	   ,ROUND((ABS(median_count_item_second - median_count_item_first) / median_count_item_first)::numeric,2) as ratio_count_item 
FROm level6)
SELECT *
FROM level7
WHERE ratio_quantity <= 0.1 AND ratio_count_item >= 0.3

-- 324. інерція клієнта

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,MAX(interval) OVER (partition by customer_id) as max_interval
FROM level2),
level4 as(SELECT *
       ,MAX(case when interval = max_interval THEN order_date END) OVER (partition by customer_id) as date_max_interval
FROM level3),
level5 as(SELECT *
       ,case when order_date < date_max_interval THEN '1_before'
	   when order_date > date_max_interval THEN '2_after'
	   when order_date = date_max_interval THEN 'pause'
	   END as gradation
FROm level4),
level6 as(SELECT *
FROM level5
WHERE gradation IN ('1_before','2_after')),
level7 as(SELECT customer_id
       ,gradation
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level6
GROUP By customer_id, gradation),
level8 as(SELECT *
FROM level6
JOIN level7 USING(customer_id, gradation)),
level9 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id,gradation order by order_date DESC) as rn_inv_before
       ,ROW_NUMBER () OVER (partition by customer_id,gradation order by order_date) as rn_after
FROM level8),
level10 as(SELECT customer_id
       ,ROUND(AVG(interval) FILTER (WHERE gradation = '1_before')::numeric,2) as avg_interval_before
	   ,ROUND(AVG(interval) FILTER (WHERE gradation = '2_after')::numeric,2) as avg_interval_after
	   ,ROUND(AVG(median_chek) FILTER (WHERE gradation = '1_before')::numeric,2) as median_chek_before
	   ,ROUND(AVG(median_chek) FILTER (WHERE gradation = '2_after')::numeric,2) as median_chek_after
FROM level9
WHERE (rn_inv_before <= 2 AND gradation = '1_before') OR (rn_after <= 2 AND gradation = '2_after')
GROUP BY customer_id),
level11 as(SELECT *
       ,ROUND((ABS(median_chek_after - median_chek_before) / median_chek_before)::numeric,2) as ratio_chek
FROM level10
WHERE avg_interval_before is not null AND avg_interval_after is not null AND
median_chek_before is not null AND median_chek_after is not null)
SELECT *
FROM level11
WHERE avg_interval_before > avg_interval_after AND ratio_chek <= 0.1

-- 325. зсув у використанні знижок

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2)::numeric,2) as middle_point
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   WHEN rn > middle_point THEN 'second_half'
	   END as halfs
       ,case when avg_discount > 0 THEN 'discount_yes'
	   when avg_discount = 0 THEN 'discount_no'
	   END as gradation
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,COUNT(*) FILTER (WHERE gradation = 'discount_yes') OVER (partition by customer_id, halfs) as count_discount_yes
	   ,COUNT(*) FILTER (WHERE gradation = 'discount_no') OVER (partition by customer_id, halfs) as count_discount_no
	   ,COUNT(*) FILTER (WHERE halfs = 'first_half') OVER (partition by customer_id) as count_order_first
	   ,COUNT(*) FILTER (WHERE halfs = 'second_half') OVER (partition by customer_id) as count_order_second
FROM level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(count_discount_yes::numeric / count_order_first::numeric) FILTER (WHERE halfs = 'first_half')::numeric,2) as discount_yes_first
	   ,ROUND(AVG(count_discount_no::numeric / count_order_first::numeric) FILTER (WHERE halfs = 'first_half')::numeric,2) as discount_no_first
	   ,ROUND(AVG(count_discount_yes::numeric / count_order_second::numeric) FILTER (WHERE halfs = 'second_half')::numeric,2) as discount_yes_second
	   ,ROUND(AVG(count_discount_no::numeric / count_order_second::numeric) FILTER (WHERE halfs = 'second_half')::numeric,2) as discount_no_second
FROM level3
GROUP By customer_id),
level5 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level2
GROUP By customer_id, halfs),
level6 as(SELECT customer_id
       ,AVG(median_quantity) FILTER (WHERE halfs = 'first_half') as median_quantity_first
	   ,AVG(median_quantity) FILTER (WHERE halfs = 'second_half') as median_quantity_second
FROM level5
GROUP By customer_id),
level7 as(SELECT *
FROM level4
JOIn level6 USING(customer_id)),
level8 as(SELECT *
       ,ROUND(ABS((median_quantity_second - median_quantity_first) / median_quantity_first)::numeric,2) as ratio_quantity
FROM level7
WHERE discount_yes_second > discount_yes_first)
SELECT *
FROM level8
WHERE ratio_quantity <= 0.1