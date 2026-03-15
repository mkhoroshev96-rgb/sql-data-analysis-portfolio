-- 296. “Клієнти з ефектом нестабільного кошика”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,ROUND(STDDEV(sum_quantity) FILTER (WHERE halfs = 'first_half')::numeric,2) as std_dev_first
	   ,ROUND(STDDEV(sum_quantity) FILTER (WHERE halfs = 'second_half')::numeric,2) as std_dev_second
FROM level2
GROUP BY customer_id)
SELECT *
FROM level3
WHERE std_dev_second > std_dev_first

-- 297. “Клієнти з ефектом перевернутого масштабу”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id,order_id,order_date),
level2 as(SELECT *
       ,case when sum_quantity < 40 THEN 'small'
	   when sum_quantity >= 40 THEN 'large'
	   END as gradation
FROm level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,ROUND(STDDEV(sum_chek) FILTER (WHERE gradation = 'small')::numeric,2) as std_dev_small
	   ,ROUND(stddev(sum_chek) FILTER (where gradation = 'large')::numeric,2) as std_dev_large
FROM level2
GROUP By customer_id)
SELECT *
FROm level3
WHERE std_dev_large > std_dev_small

-- 298. “Клієнти з ілюзією стабільності”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price * (1-discount))::numeric,2) as avg_price
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER() OVER(partition by customer_id order by order_date) as rn
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id,order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_chek_second
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_quantity_second
	   ,ROUND(AVG(avg_price) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_price_first
	   ,ROUND(AVG(avg_price) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_price_second
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND((ABS(avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,2) as ratio_chek
	   ,ROUND((ABS(avg_quantity_second - avg_quantity_first) / avg_quantity_first)::numeric,2) as ratio_quantity
	   ,ROUND((ABS(avg_price_second - avg_price_first) / avg_price_first)::numeric,2) as ratio_price
FROM level3),
level5 as(SELECT *
FROM level4
WHERE ratio_chek <= 0.1),
level6 as(SELECT *
FROM level5
WHERE (avg_quantity_second > avg_quantity_first AND avg_price_second < avg_price_first) 
OR (avg_quantity_second < avg_quantity_first AND avg_price_second > avg_price_first))
SELECT *
FROM level6
WHERE (ratio_quantity >= 0.25 AND ratio_price <= 0.25) 
OR (ratio_quantity <= 0.25 AND ratio_price >= 0.25)

-- 299. “Клієнти з ламаною внутрішньою логікою замовлень”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROUND(AVG(unit_price * (1-discount))::numeric,2) as avg_price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(corr(sum_quantity, sum_chek)::numeric,2) as corr_qnt_chek
	   ,ROUND(corr(avg_price,sum_chek)::numeric,2) as corr_price_chek
FROM level1
WHERE count_order >= 6
GROUP By customer_id)
SELECT *
WHERE corr_qnt_chek <= 0.3 AND corr_price_chek >= 0.7

-- 300. “Клієнти з парадоксом ефективності замовлень”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROUND(AVG(unit_price * (1-discount))::numeric,2) as avg_price
	   ,ROUND((SUM(unit_price * quantity * (1-discount)) / SUM(quantity))::numeric,2) as chek_per_item
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id,order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level1
WHERE count_order >= 6
GROUP By customer_id),
level3 as(SELECT *
       ,case when sum_quantity <= median_quantity Then 'small'
	   when sum_quantity > median_quantity THEN 'large'
	   END as gradation
FROM level1
JOIN level2 USING (customer_id)),
level4 as(SELECT customer_id
       ,ROUND(AVG(chek_per_item) FILTER (WHERE gradation = 'small')::numeric,2) as avg_chek_per_item_small
	   ,ROUND(AVG(chek_per_item) FILTER (WHERE gradation = 'large')::numeric,2) as avg_chek_per_item_large
	   ,ROUND(AVG(avg_price) FILTER (WHERE gradation ='small')::numeric,2) as avg_price_small
	   ,ROUND(AVG(avg_price) FILTER (WHERE gradation = 'large')::numeric,2) as avg_price_large
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND((ABS(avg_price_large - avg_price_small) / avg_price_small)::numeric,2) as ratio_price
FROM level4)
SELECT *
FROM level5
WHERE ratio_price <= 0.1 AND avg_chek_per_item_large > avg_chek_per_item_small

-- 301. “Клієнти з розривом внутрішньої логіки кошика”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND((unit_price * (1-discount))::numeric,2) as real_price
	   ,quantity
	   ,SUM(quantity) OVER (partition by customer_id) as total_quantity
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
	   ,ROUND(SUM(unit_price * quantity * (1-discount)) OVER (partition by customer_id)::numeric,2) as total_chek
FROm orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by real_price) as median_price
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,case when real_price < median_price THEN 'cheap_items'
	   when real_price >= median_price THEN 'expensive_items'
	   END as gradation
FROM level1
JOIN level2 USING (customer_id)),
level4 as(SELECT *
       ,SUM(chek) FILTER (WHERE gradation = 'expensive_items') OVER (partition by customer_id) as sum_chek_expensive
	   ,SUM(chek) FILTER (WHERE gradation = 'cheap_items') OVER (partition by customer_id) as sum_chek_cheap
	   ,SUM(quantity) FILTER (WHERE gradation = 'expensive_items') OVER (partition by customer_id) as sum_quantity_expensive
	   ,SUM(quantity) FILTER (WHERE gradation = 'cheap_items') OVER (partition by customer_id) as sum_quantity_cheap
FROM level3),
level5 as(SELECT DISTINCT customer_id
       ,ROUND((sum_chek_expensive / total_chek)::numeric,2) as ratio_expensive_chek
	   ,ROUND((sum_chek_cheap / total_chek)::numeric,2) as ratio_cheap_chek
	   ,ROUND((sum_quantity_expensive::numeric / total_quantity::numeric),2) as ratio_expensive_quantity
	   ,ROUND((sum_quantity_cheap::numeric / total_quantity::numeric),2) as ratio_cheap_quantity
FROM level4)
SELECT *
FROM level5
WHERE ratio_cheap_quantity >= 0.5 AND ratio_cheap_chek >= 0.5 AND ratio_expensive_chek <= 0.5 

-- 302. “Клієнти з локальним парадоксом замовлень”

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
       ,LAG(sum_quantity) OVER (PARTITIon by customer_id order by order_date) as prev_quantity
	   ,LEAD(sum_quantity) OVER (PARTITION by customer_id order by order_date) as next_quantity
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,CASE when sum_quantity < prev_quantity AND sum_quantity < next_quantity THEN 1 ELSE 0 END as flag_quantity
	   ,case when sum_chek > prev_chek AND sum_chek > next_chek THEN 1 ELSE 0 END as flag_chek
FROM level2
WHERE prev_quantity is not null 
AND next_quantity is not null 
AND prev_chek is not null 
AND next_chek is not null),
level4 as(SELECT *
       ,case when flag_quantity = 1 AND flag_chek = 1 THEN 1 ELSE 0 END as summary_flag
FROM level3),
level5 as(SELECT *
       ,SUM(summary_flag) OVER (partition by customer_id) as sum_summary_flag
FROM level4)
SELECT *
FROm level5
WHERE sum_summary_flag >= 2

-- 303. “Клієнти з різким гальмуванням”

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id,order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 4),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta
FROM level2
where prev_chek is not null)
SELECT *
FROM level3
WHERE delta < 0 AND ABS(delta) >= prev_chek * 0.5