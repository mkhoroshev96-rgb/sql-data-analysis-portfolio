--619. «Клієнт з ефектом порушеної причинності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(avg(unit_price)::numeric,2) as avg_price
	   ,ROUND(avg(discount)::numeric,4) as avg_discount
	   ,COUNT(order_id) over (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(avg_discount) OVER (partition by customer_id order by order_date) as prev_avg_discount
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,case when avg_discount >= 2 * prev_avg_discount THEN 1 
	   ELSE 0 END as flag_discount
	   ,LAG(avg_price,1) OVER (partition by customer_id order by order_date) as prev_1_avg_price
	   ,LAG(avg_price,2) OVER (partition by customer_id order by order_date) as prev_2_avg_price
FROm level2
WHERE prev_avg_discount is not null),
level4 as(SELECT *
       ,ROUND(ABS((prev_1_avg_price - prev_2_avg_price) / prev_2_avg_price)::numeric,2) as diff_prev_1_and_2
	   ,ROUND(ABS((avg_price - prev_1_avg_price) / prev_1_avg_price)::numeric,2) as diff_prev_1
FROM level3
WHERE prev_2_avg_price is not null),
level5 as(SELECT *
       ,count(order_id) OVER (partition by customer_id) as count_cases
FROm level4
WHERE diff_prev_1_and_2 >= 0.1 AND diff_prev_1 < 0.05 AND flag_discount = 1)
SELECT *
FROm level5
WHERE count_cases >= 1

-- 620. «Клієнт з ефектом асиметричного навчання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,ROUND(AVG(discount)::numeric,2) as avg_discount
	   ,count(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(avg_discount) OVER (partition by customer_id order by order_date) as prev_avg_discount 
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,case when avg_discount >= prev_avg_discount + 0.1 THEN 'gain'
	   when avg_discount <= prev_avg_discount - 0.1 THEN 'loss'
	   END as reward
	   ,LEAD(avg_price) OVER (partition by customer_id order by order_date) as next_avg_price
FROM level2
WHERE prev_avg_discount is not null),
level4 as(SELECT *
       ,case when reward = 'gain' AND next_avg_price <= 0.95 * avg_price THEN 1
	   ELSE 0 END as flag_next_price_gain
	   ,case when reward = 'loss' AND next_avg_price < 1.05 * avg_price THEN 1
	   ELSE 0 END as flag_next_price_loss
FROM level3
WHERE next_avg_price is not null),
level5 as(SELECT *
       ,SUM(flag_next_price_gain) OVER (partition by customer_id) as sum_flag_next_price_gain
	   ,SUM(flag_next_price_loss) OVER (partition by customer_id) as sum_flag_next_price_loss
FROm level4)
SELECT *
FROM level5
WHERE sum_flag_next_price_gain >= 1 AND sum_flag_next_price_loss >= 1

-- 621. «Клієнт з ефектом порогової чутливості»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(avg_discount) OVER (partition by customer_id order by order_date) as prev_avg_discount
FROM level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,ABS(avg_discount - prev_avg_discount) as abs_delta_discount
FROm level2
WHERE prev_avg_discount is not null),
level4 as(SELECT *
       ,case when abs_delta_discount < 0.05 THEN 'small'
	   when abs_delta_discount >= 0.15 THEN 'large'
	   END as change
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROm level3),
level5 as(SELECT *
       ,ROUND(ABS((next_chek - sum_chek) / sum_chek)::numeric,2) as delta_chek
FROm level4),
level6 as(SELECT *
       ,case when delta_chek < 0.05 THEN 'low'
	   when delta_chek >= 0.1 THEN 'high'
	   END as gradation_chek
FROM level5),
level7 as(SELECT *
       ,COUNT(order_id) FILTER (WHERE gradation_chek = 'high' AND change = 'large') OVER (partition by customer_id) as count_order_high
	   ,COUNT(order_id) FILTER (WHERE gradation_chek = 'low' AND change = 'small') OVER (partition by customer_id) as count_order_low
FROm level6)
SELECT *
FROm level7
WHERE count_order_high >= 1 AND count_order_low >= 1

-- 622. «Клієнт з ефектом бюджетного якоря»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,MAX(discount) as max_discount
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order 
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when max_discount >= 0.25 THEN 1 ELSE 0 END as flag_discount
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,ROUND(ABS((next_chek - avg_chek) / avg_chek)::numeric,2) as diff_chek
FROm level2
WHERE flag_discount = 1),
level4 as(SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as real_count
FROM level3
WHERE diff_chek <= 0.05)
SELECT *
FROm level4
WHERE real_count >= 2

-- 623. «Клієнт з ефектом вибіркового апгрейду»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(avg_price) OVER (partition by customer_id order by order_date) as next_price
	   ,LEAD(sum_quantity) OVER (partition by customer_id order by order_date) as next_quantity
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,ROUND(ABS((next_chek - sum_chek) / sum_chek) ::numeric,2) as diff_chek
FROm level2
WHERE next_chek is not null),
level4 as(SELECT *
       ,case when next_price >= avg_price * 1.1 AND diff_chek <= 0.05 AND next_quantity <= sum_quantity * 0.9 THEN 1
	   ELSE 0 END as summary_flag
FROM level3),
level5 as(SELECT *
       ,SUM(summary_flag) OVER (partition by customer_id) as sum_summary_flag
FROm level4)
SELECT *
FROm level5
WHERE sum_summary_flag >= 2

-- 624. «Клієнт з ефектом компенсаторної швидкості»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,shipped_date - order_date as delivery_time
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details Using (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(delivery_time) OVER (partition by customer_id order by order_date) as next_delivery
	   ,LEAD(avg_price) OVER (partition by customer_id order by order_date) as next_price
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,next_delivery - delivery_time as delta_delivery
	   ,ROUND((next_price / avg_price)::numeric,2) as delta_price
	   ,ROUND((next_chek / sum_chek)::numeric,2) as delta_chek
FROM level2
WHERE next_delivery is not null),
level4 as(SELECT *
       ,case when delta_delivery >= 3 AND (delta_price >= 1.1 OR delta_chek >= 1.15) THEN 1
	   ELSE 0 END as total_flag
FROm level3),
level5 as(SELECT *
       ,SUM(total_flag) OVER (PARTITION BY customer_id) as sum_total_flag
FROM level4)
SELECT *
FROm level5
WHERE sum_total_flag >= 2

-- 625. «Клієнт з ефектом внутрішнього обману очікувань»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND((SUM(unit_price * quantity) / sum(quantity))::numeric,2) as price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
       ,LEAD(price) OVER (partition by customer_id order by order_date) as next_price
FROM level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,case when next_price > price THEN 1 ELSE 0 END as flag_price
FROM level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(price) FILTER (WHERE halfs = 'first')::numeric,2) as avg_price_first
	   ,ROUND(AVG(price) FILTER (WHERE halfs = 'second')::numeric,2) as avg_price_second
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND(ABS((avg_price_second - avg_price_first) / avg_price_first)::numeric,2) as diff_avg_price
	   ,SUM(flag_price) OVER (partition by customer_id) as sum_flag_price
FROm level3
JOIN level4 USING (customer_id)
WHERE next_price is not null)
SELECT *
FROM level5
WHERE diff_avg_price <= 0.05 AND sum_flag_price >= 3

-- 626. «Клієнт з ефектом зсуву норми»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND((SUM(unit_price * quantity) / sum(quantity))::numeric,2) as price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
	   ,ROUND(AVG(price) OVER (partition by customer_id)::numeric,2) as avg_price
FROM level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,case when price > 1.15 * avg_price THEN 1 ELSE 0 END as flag_price
FROm level2),
level4 as(SELECT customer_id
       ,SUM(flag_price) FILTER (WHERE halfs = 'first') as count_price_first
	   ,SUM(flag_price) FILTER (WHERE halfs = 'second') as count_price_second
FROm level3
GROUP BY customer_id)
SELECT *
FROM level4
WHERE count_price_first = 1 AND count_price_second >= 3