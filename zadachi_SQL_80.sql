-- 507. «Клієнт з ефектом інерційного зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date)
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_quantity) OVER (partition by customer_id order by order_date) as next_quantity
FROm level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta_chek
	   ,next_quantity - sum_quantity as delta_quantity
FROM level2
WHERE prev_chek is not null AND next_quantity is not null),
level4 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by delta_chek)::numeric,2) as median_delta_chek
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by delta_quantity)::numeric,2) as median_delta_quantity
FROM level3
GROUP BY customer_id)
SELECT *
FROM level3
JOIN level4 USING (customer_id)
WHERE median_delta_chek > 0 AND median_delta_quantity > 0

-- 508. «Клієнт з ефектом помилкової оптимізації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((sum_chek / sum_quantity)::numeric,2) as avg_price_item
FROM level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,corr(sum_quantity, avg_price_item) as corr_qnt_price
	   ,corr(sum_quantity, sum_chek) as corr_qnt_chek
FROm level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
FROM level4
WHERE corr_qnt_price < 0 AND corr_qnt_chek <= 0)
SELECT *
FROm level5
WHERE diff_chek <= 0.1

-- 509. «Клієнт з ефектом асиметричної реакції»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,shipped_date - order_date as delivery_days
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(delivery_days) OVER (partition by customer_id order by order_date) as prev_delivery
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek 
FROM level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,delivery_days - prev_delivery as delta_delivery
	   ,sum_chek - prev_chek as delta_chek
FROM level2),
level4 as(SELECT *
       ,case when delta_delivery < 0 THEN 'improve'
	   when delta_delivery > 0 THEN 'worsen'
	   when delta_delivery = 0 THEN 'equal'
	   END as gradation
FROM level3
WHERE prev_delivery is not null and prev_chek is not null),
level5 as(SELECT customer_id
       ,ROUND(AVG(delta_chek) FILTER (WHERE gradation = 'improve')::numeric,2) as avg_delta_chek_improve
	   ,ROUND(AVG(delta_chek) FILTER (WHERE gradation = 'worsen')::numeric,2) as avg_delta_chek_worsen
FROM level4
WHERE gradation IN ('improve', 'worsen')
GROUP BY customer_id)
SELECT *
FROM level5
WHERE avg_delta_chek_improve <= 0 AND avg_delta_chek_worsen < 0

-- 510. «Клієнт з ефектом втраченої послідовності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROm level1
WHERE count_order > 9),
level3 as(SELECT *
       ,case when sum_chek > avg_chek THEN 'high'
	   when sum_chek < avg_chek THEN 'low'
	   when sum_chek = avg_chek then 'equal'
	   END as gradation
FROM level2),
level4 as(SELECT *
       ,LEAD(gradation) OVER (partition by customer_id order by order_date) as next_gradation
FROM level3
WHERE gradation IN ('high', 'low')),
level5 as(SELECT *
       ,case when gradation = 'low' AND next_gradation = 'low' THEN 1 ELSE 0 END as flag_low
	   ,case when gradation = 'high' AND next_gradation = 'high' THEN 1 ELSE 0 END as flag_high
FROM level4
WHERE next_gradation is not null),
level6 as(SELECT *
       ,SUM(flag_low) OVER (partition by customer_id) as sum_flag_low
	   ,SUM(flag_high) OVER (partition by customer_id) as sum_flag_high
	   ,COUNT(order_id) OVER (partition by customer_id) as real_count_order
FROM level5),
level7 as(select *
       ,ROUND((sum_flag_low::numeric / real_count_order::numeric),2) as ratio_low
	   ,ROUND((sum_flag_high::numeric / real_count_order::numeric),2) as ratio_high
	   ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
FROM level6)
SELECT *
FROM level7
WHERE ratio_high < ratio_low AND diff_chek <= 0.1

-- 511. «Клієнт з ефектом розірваної відповідності»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,sum(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as (SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek
	   ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
	   ,ROUND(STDDEV(sum_quantity) OVER (partition by customer_id)::numeric,2) as std_dev_quantity
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1),
level3 as(SELECT *
       ,case when ABS(sum_chek - avg_chek) <= 0.5 * std_dev_chek THEN 'yes' 
	   ELSE 'no' END as stable_chek
	   ,case when ABS(sum_quantity - avg_quantity) <= 0.5 * std_dev_quantity THEN 'yes'
	   ELSE 'no' END as stable_quantity
	   ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
FROM level2),
level4 as(SELECT *
       ,case when stable_chek = 'yes' AND stable_quantity = 'no' THEN 1 ELSE 0 END as flag_chek_qnt
	   ,case when stable_chek = 'no' AND stable_quantity = 'yes' THEN 1 ELSE 0 END as flag_qnt_chek
FROM level3
WHERE count_order >= 9),
level5 as(SELECT *
       ,SUM(flag_chek_qnt) OVER (partition by customer_id) as sum_flag_chek_qnt
	   ,SUM(flag_qnt_chek) OVER (partition by customer_id) as sum_flag_qnt_chek
FROM level4),
level6 as(SELECT *
       ,ROUND((sum_flag_chek_qnt::numeric / count_order::numeric),2) as ratio_chek_qnt
	   ,ROUND((sum_flag_qnt_chek::numeric / count_order::numeric),2) as ratio_qnt_chek
FROm level5)
SELECT *
FROM level6
WHERE diff_chek <= 0.1 and ratio_chek_qnt > 0.3 AND ratio_qnt_chek > 0.3

-- 512. «Клієнт з ефектом запізнілого впливу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,shipped_date - order_date as delivery_days
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(delivery_days) OVER (partition by customer_id order by order_date) as prev_delivery
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1),
level3 as(SELECT *
       ,delivery_days - prev_delivery as delta_delivery
	   ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
FROM level2
WHERE count_order >= 9),
level4 as(SELECT *
       ,case when delta_delivery > 0 then 'bad'
	   else 'good' END as service
	   ,LEAD(sum_chek,1) OVER (partition by customer_id order by order_date) as next_1_chek
	   ,LEAD(sum_chek,2) OVER (partition by customer_id order by order_date) as next_2_chek
FROm level3),
level5 as(SELECT *
       ,next_2_chek - sum_chek as delayed_delta_chek
	   ,next_1_chek - sum_chek as delta_chek_immediate
FROM level4
WHERE service = 'bad'),
level6 as(SELECT *
       ,ROUND(AVG(delayed_delta_chek) FILTER (WHERE service = 'bad') OVER (partition by customer_id)::numeric,2) as avg_delta_chek_2
	   ,ROUND(AVG(delta_chek_immediate) FILTER (WHERE service = 'bad') OVER (partition by customer_id)::numeric,2) as avg_delta_chek_1
FROm level5)
SELECT *
FROM level6
WHERE avg_delta_chek_2 < 0 AND diff_chek <= 0.1 AND avg_delta_chek_1 >= 0

-- 513. «Клієнт з ефектом хибної компенсації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,shipped_date - order_date as delivery_days
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by delivery_days) as median_delivery
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when delivery_days > median_delivery THEN 'bad'
	   ELSE 'other' END as service
	   ,LEAD(sum_chek,1) OVER (partition by customer_id order by order_date) as next_1_chek
	   ,LEAD(sum_chek,2) OVER (partition by customer_id order by order_date) as next_2_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1
JOIN level2 USING (customer_id)),
level4 as(SELECT *
       ,next_1_chek - sum_chek as delta_chek_immediate
	   ,next_2_chek - sum_chek as delta_chek_delayed
FROM level3
WHERE service = 'bad' and count_order >= 9),
level5 as(SELECT *
       ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
FROM level4
WHERE delta_chek_immediate is not null AND delta_chek_delayed is not null),
level6 as(SELECT customer_id
       ,ROUND(AVG(delta_chek_immediate)::numeric,2) as avg_delta_chek_immediate
	   ,ROUND(AVG(delta_chek_delayed)::numeric,2) as avg_delta_chek_delayed
FROM level5
WHERE diff_chek <= 0.1
GROUP BY customer_id)
SELECT *
FROm level6
WHERE avg_delta_chek_immediate > 0 AND avg_delta_chek_delayed < 0

-- 514. кількість різних днів тижня в базі норсвінд

WITH level1 as(SELECT order_date 
       ,EXTRACT(dow from order_date) as dow
FROM orders)
SELECT dow
       ,COUNT(dow) as count_dow
FROm level1
GROUP BY dow




