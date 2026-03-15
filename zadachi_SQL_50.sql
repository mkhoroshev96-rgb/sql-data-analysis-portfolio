-- 315. “Клієнти з нестабільним розміром кошика”

With level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,Lead(sum_quantity) Over (partition by customer_id order by order_date) as next_quantity
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,ROUND((sum_quantity::numeric / prev_quantity::numeric * 100),2) as ratio_prev_qnt
	   ,ROUND((sum_quantity::numeric / next_quantity::numeric * 100),2) as ratio_next_qnt
FROM level2
WHERE prev_quantity is not null AND next_quantity is not null),
level4 as(SELECT *
       ,case when ratio_prev_qnt >= 200 OR ratio_next_qnt >= 200 THEN 1 ELSE 0 END as flag_high
	   ,case when ratio_prev_qnt <= 50 OR ratio_next_qnt <= 50 THEN 1 ELSE 0 END as flag_low
FROM level3),
level5 as(SELECT *
       ,SUM(flag_high) OVER (partition by customer_id) as sum_flag_high
	   ,SUM(flag_low) OVER (partition by customer_id) as sum_flag_low
FROM level4)
SELECT *
FROM level5
WHERE sum_flag_high >= 1 AND sum_flag_low >= 1

-- 316. “Клієнти з ефектом зламаної стабільності”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id,order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half' 
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROm level2
GROUP By customer_id, halfs),
level4 as(SELECT customer_id
       ,AVG(median_quantity) FILTER (WHERE halfs = 'first_half') as median_quantity_first
	   ,AVG(median_quantity) FILTER (WHERE halfs = 'second_half') as median_quantity_second
	   ,ROUND(AVG(avg_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(avg_chek) FILTER (where halfs = 'second_half')::numeric,2) as avg_chek_second
FROM level2
JOIN level3 USING(customer_id, halfs)
GROUP By customer_id)
SELECT *
FROM level4
WHERE median_quantity_first > median_quantity_second AND avg_chek_second > avg_chek_first

-- 317. “Клієнти з ефектом ілюзії зростання”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((sum_chek / sum_quantity)::numeric,2) as price_per_item
	   ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,SUM(sum_chek) FILTER (WHERE halfs = 'first_half') as total_revenue_first
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'second_half') as total_revenue_second
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_quantity_second
	   ,ROUND(AVG(price_per_item) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_price_per_item_first
	   ,ROUND(AVG(price_per_item) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_price_per_item_second
FROm level2
GROUP By customer_id)
SELECT *
FROM level3
WHERE total_revenue_second > total_revenue_first 
AND avg_quantity_first > avg_quantity_second
AND avg_price_per_item_first > avg_price_per_item_second

-- 318. “Клієнти з парадоксом стабільної суми”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) /2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id,order_date),
level2 as(SELECT *
FROM level1),
level3 as(SELECT customer_id
       ,order_id
	   ,COUNT(*) as count_item_in_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level4 as(SELECT *
       ,case when rn <= middle_point THEn 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level2
JOIN level3 USING(customer_id, order_id)),
level5 as(SELECT customer_id
       ,SUM(sum_chek) FILTER (WHERE halfs = 'first_half') as total_revenue_first
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'second_half') as total_revenue_second
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_quantity_second
	   ,ROUND(AVG(count_item_in_order) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_count_item_first
	   ,ROUND(AVG(count_item_in_order) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_count_item_second
FROM level4
GROUP By customer_id),
level6 as(SELECT *
       ,ROUND((ABS(total_revenue_second - total_revenue_first) / total_revenue_first)::numeric,2) as ratio_revenue
	   ,ROUND((ABS(avg_quantity_second - avg_quantity_first) / avg_quantity_first)::numeric,2) as ratio_quantity
	   ,ROUND((ABS(avg_count_item_second - avg_count_item_first) / avg_count_item_first)::numeric,2) as ratio_count_item
FROM level5)
SELECT *
FROM level6
WHERE ratio_revenue <= 0.05 AND ratio_quantity >= 0.3 AND ratio_count_item >= 0.3

-- 319. “Клієнти з ефектом ламаної памʼяті”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 7),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
FROM level2
JOIN level3 USING(customer_id)),
level5 as(SELECT *
       ,case when sum_quantity >= 1.8 * median_quantity OR sum_quantity <= 0.55 * median_quantity THEN 1 ELSE 0 END as flag_quantity
	   ,case when sum_chek >= 1.8 * median_chek OR sum_chek <= 0.55 * median_chek THEN 1 ELSE 0 END as flag_chek
FROM level4),
level6 as(SELECT *
       ,case when (flag_quantity = 1 AND flag_chek = 1) THEN 1 ELSE 0 END as flag_chek_qnt 
FROM level5),
level7 as(SELECT *
       ,LAG(flag_chek_qnt) OVER (partition by customer_id order by order_date) as prev_flag_chek_qnt
	   ,LEAD(flag_chek_qnt) OVER (partition by customer_id order by order_date) as next_flag_chek_qnt
FROM level6),
level8 as(SELECT *
       ,case when prev_flag_chek_qnt = 1 AND flag_chek_qnt = 0 AND next_flag_chek_qnt = 1 THEN 1 ELSE 0 END as summary_flag
FROm level7
WHERE prev_flag_chek_qnt is not null AND next_flag_chek_qnt is not null),
level9 as(SELECT *
       ,SUM(summary_flag) OVER (partition by customer_id) as sum_summary_flag
FROM level8)
SELECT *
FROM level9
WHERE sum_summary_flag >= 3

-- 320. “Клієнти з ефектом втраченої інерції”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,MAX(interval) OVER (partition by customer_id) as max_interval
FROM level2),
level4 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by interval) as median_interval
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND((max_interval::numeric / median_interval::numeric),2) as ratio_interval
FROM level3
JOIN level4 USING(customer_id)),
level6 as(SELECT customer_id
       ,MAX(case when max_interval = interval Then order_date END) as max_date_in_interval
FROM level5
WHERE ratio_interval >= 2
GROUP By customer_id),
level7 as(SELECT *
       ,case when order_date < max_date_in_interval THEN 'before'
	   when order_date > max_date_in_interval THEN 'after'
	   when order_date = max_date_in_interval Then 'pause'
	   END as gradation
FROM level5
JOIN level6 USING(customer_id)),
level8 as(SELECT *
FROM level7
WHERE gradation In ('before','after')),
level9 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (where gradation = 'before')::numeric,2) as avg_quantity_first
	   ,ROUND(Avg(sum_quantity) FILTER (where gradation = 'after')::numeric,2) as avg_quantity_second
	   ,ROUND(AVG(sum_chek) FILTER (where gradation = 'before')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (where gradation = 'after')::numeric,2) as avg_chek_second
FROM level8
GROUP By customer_id)
SELECT *
FROM level9
WHERE avg_quantity_first <= avg_quantity_second AND avg_chek_first <= avg_chek_second