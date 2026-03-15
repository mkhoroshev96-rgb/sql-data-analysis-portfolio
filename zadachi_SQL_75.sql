-- 474. «Клієнт із фальшивою лояльністю»

WITH block1 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,employee_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN employees USING (employee_id)
GROUP BY customer_id, order_id, employee_id
ORDER BY customer_id, order_id, employee_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by sum_chek) FROM level1) as global_median_chek
	   ,COUNT(order_id) OVER (partition by customer_id, employee_id) as count_employes
FROM level1),
level3 as(SELECT DISTINCT customer_id,employee_id
       ,count_order
	   ,avg_chek
	   ,global_median_chek
	   ,count_employes
FROM level2),
level4 as(SELECT *
       ,ROUND((count_employes::numeric / count_order::numeric),2) as ratio 
FROM level3),
level5 as(SELECT *
       ,MAX(ratio) OVER (partition by customer_id) as max_ratio
FROM level4)
SELECT *
FROM level5
WHERE max_ratio >= 0.6 and avg_chek < global_median_chek),
block2 as(WITH level1 as(SELECT customer_id
	   ,product_id
FROM orders
JOIN order_details USING (order_id)
Order BY customer_id),
level2 as(SELECT customer_id
	   ,COUNT(DISTINCT product_id) as count_unik_prod
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by count_unik_prod) FROM level2) as global_median_count
FROM level2)
SELECT *
FROM level3
WHERE count_unik_prod < global_median_count)
SELECT *
FROM block1
JOIN block2 USING (customer_id)

-- 475. «Клієнт із втраченою інерцією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_last
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn_last = 1 THEN 'last'
	   when rn_last >= 2 THEN 'other'
	   END as groups
FROM level1),
level3 as(SELECT customer_id
       ,AVG(sum_quantity) FILTER (WHERE groups = 'last') as avg_qnt_last
	   ,AVG(sum_quantity) FILTER (WHERE groups = 'other') as avg_qnt_other
	   ,AVG(sum_chek) FILTER (WHERE groups = 'last') as avg_chek_last
	   ,AVG(sum_chek) FILTER (WHERE groups = 'other') as avg_chek_other
FROM level2
GROUP BY customer_id)
SELECT *
FROM level3
WHERE avg_chek_last < avg_chek_other AND avg_qnt_last > avg_qnt_other

-- 476. «Замовлення з ефектом фальшивого росту»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,sum(quantity) as sum_quantity 
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((sum_chek / sum_quantity),2) as avg_price_per_item
FROm level1),
level3 as(SELECT *
       ,LAG(avg_price_per_item) OVER (partition by customer_id order by order_date) as prev_avg_price_per_item
	   ,LAG(sum_chek) OVER (partition  by customer_id order by order_date) as prev_chek
FROM level2)
SELECT *
FROM level3
WHERE avg_price_per_item > prev_avg_price_per_item
AND sum_chek < prev_chek

-- 477. «Клієнт з ефектом звуження кошика»

WITH level1 as(select customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id) / 2)::numeric,2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((sum_chek / sum_quantity)::numeric,2) as avg_price_item
	   ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second')::numeric,2) as avg_quantity_second
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,ROUND(AVG(avg_price_item) FILTER (WHERE halfs = 'first')::numeric,2) as avg_price_item_first
	   ,ROUND(AVG(avg_price_item) FILTER (WHERE halfs = 'second')::numeric,2) as avg_price_item_second
FROM level2
GROUP By customer_id)
SELECT *
FROM level3
WHERE avg_quantity_second < avg_quantity_first
AND avg_price_item_second > avg_price_item_first
AND avg_chek_second <= avg_chek_first

-- 478. «Клієнт, який ламає власне середнє»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_customer
FROM level1),
level3 as(SELECT DISTINCT customer_id
       ,avg_chek_customer
	   ,count_order
FROM level2),
level4 as(SELECT *
       ,ROUND(AVG(avg_chek_customer) OVER ()::numeric,2) as global_avg_chek
FROM level3),
level5 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as chek_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level6 as(SELECT *
       ,case when chek_order > avg_chek_customer THEN 1 ELSE 0 END as flag_chek
FROM level5
JOIN level4 USING (customer_id)
ORDER BY customer_id, order_id),
level7 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level6)
SELECT *
FROM level7
WHERE count_order = sum_flag_chek

-- 479. «Замовлення, яке з’їло категорію»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,category_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
GROUP BY customer_id, order_id, category_id
ORDER BY customer_id, order_id),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id, order_id) as total_chek_order
	   ,SUM(sum_quantity) OVER (partition by customer_id, order_id) as total_quantity_order
FROM level1),
level3 as(SELECT *
       ,ROUND((sum_chek / total_chek_order)::numeric,2) as ratio_chek
	   ,ROUND((sum_quantity / total_quantity_order)::numeric,2) as ratio_quantity
FROM level2)
SELECT *
FROm level3
WHERE ratio_chek >= 0.8 AND ratio_quantity < 0.8

-- 480. «Клієнт із дзеркальною поведінкою»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,ROW_NUMBER () OVER (partition by customer_id Order by order_date) as rn_first
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_last
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn_first = 1 THEN 'first_value' ELSE 'other' END as first_other
	   ,case when rn_last = 1 THEN 'last_value' ELSE 'other' END as last_other
FROm level1),
level3 as(SELECT *
       ,ROUND(AVG(sum_quantity) FILTER (WHERE first_other = 'first_value') OVER (partition by customer_id)::numeric,2) as quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE last_other = 'last_value') OVER (partition by customer_id)::numeric,2) as quantity_last
FROM level2),
level4 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE first_other = 'other' AND last_other = 'other') OVER (partition by customer_id)::numeric,2) as avg_chek_other
	   ,ROUND(AVG(sum_chek) FILTER (WHERE first_other = 'first_value') OVER (partition by customer_id)::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE last_other = 'last_value') OVER (partition by customer_id)::numeric,2) as avg_chek_last
FROM level3
WHERE quantity_first = quantity_last),
level5 as(SELECT *
       ,case when avg_chek_other BETWEEN avg_chek_first AND avg_chek_last THEN 'yes'
	   ELSE 'no' END as gradation
FROM level4
WHERE avg_chek_other is not null AND avg_chek_first <> avg_chek_last)
SELECT *
FROm level5
WHERE gradation = 'yes'

-- 481. «Клієнт із внутрішнім конфліктом»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_last
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when rn_last = 1 THEn 'last_value'
	   when rn_last >= 2 THEN 'other'
	   END as last_other
FROM level1
JOIN level2 USING (customer_id)),
level4 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE last_other = 'last_value') OVER (partition by customer_id)::numeric,2) as chek_last_order
FROM level3
WHERE median_chek > avg_chek)
SELECT *
FROm level4
WHERE chek_last_order < avg_chek AND chek_last_order < median_chek

-- 482. Медіаний чек дорівнює середньому чеку (або дуже близький до цього)

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
FROM level1
GROUP BY customer_id),
level3 as(SELECT DISTINCT customer_id
       ,avg_chek
	   ,median_chek
	   ,ABS(avg_chek - median_chek) as diff
FROM level1
JOIN level2 USING (customer_id))
SELECT *
FROM level3
WHERE avg_chek = median_chek
